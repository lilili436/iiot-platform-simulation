package org.example.iiot.demo;
import java.util.*;
import java.nio.file.*;
import java.nio.charset.StandardCharsets;
import java.io.IOException;
import org.example.iiot.*;
import org.example.iiot.config.ScenarioLoader.Data;
import org.example.iiot.model.*;
import org.example.iiot.placement.*;
import org.example.iiot.metrics.PlatformAudit;

public final class DemoEngine {
    private final Data data;
    private final Path journal;
    private final String session=UUID.randomUUID().toString();
    private final Set<String> offline=new HashSet<>();
    private Map<String,PlatformPolicy.Capabilities> caps;
    private PlanRuntime.Run run;
    private String algorithm="beam_search",phase="RUNNING",fault="",faultNode="";
    private boolean playing=true,cooling=false;
    private int tick=0,normalSamples=0;
    private double heat=0;
    private final List<Map<String,Object>> samples=new ArrayList<>(),history=new ArrayList<>(),diagnosis=new ArrayList<>(),moves=new ArrayList<>();
    public DemoEngine(Data data,Path journal)throws IOException{this.data=data;this.journal=journal;Files.createDirectories(journal.toAbsolutePath().getParent());reset("beam_search");}
    private void event(String kind,String text){
        Map<String,Object> e=Map.of("step",tick,"kind",kind,"text",text);
        history.add(e);
        if(history.size()>120)history.remove(0);
        try{Files.writeString(journal,Json.write(Map.of("session",session,"step",tick,"kind",kind,"text",text))+"\n",StandardCharsets.UTF_8,StandardOpenOption.CREATE,StandardOpenOption.APPEND);}
        catch(IOException ex){throw new IllegalStateException("Cannot persist demo journal",ex);}
    }
    private void reset(String selected){
        if(!Set.of("beam_search","first_fit","round_robin","best_fit").contains(selected))throw new IllegalArgumentException("Invalid algorithm");
        algorithm=selected;offline.clear();caps=new LinkedHashMap<>(data.nodeCapabilities());fault="";faultNode="";heat=0;cooling=false;
        tick=0;normalSamples=0;phase="RUNNING";playing=true;samples.clear();diagnosis.clear();moves.clear();history.clear();
        run=PlanRuntime.run(data,algorithm,64,data.nodes(),caps);
        sample();event("READY","初始化完成：Java规划与CloudSim部署事件已执行；当前为合成工业环境。");
    }
    private Set<String> available(){
        PlatformPolicy.configureExternal("demo","full",caps,data.variantRequirements());
        Set<String> local=new HashSet<>();
        for(var a:run.plan().assignments())if(!offline.contains(a.node().id())&&
            PlatformPolicy.declaredRejectionReasons(a.variant(),a.node()).isEmpty()&&run.ready().contains(a.serviceId()))local.add(a.serviceId());
        return PlatformAudit.dependencyClosedReady(data.services(),local);
    }
    private void sample(){
        double temperature=58+2*Math.sin(tick*.31)+heat;
        double vibration=2.2+.25*Math.sin(tick*.55)+heat/12;
        boolean alarm=temperature>=80||vibration>=6;
        normalSamples=alarm?0:normalSamples+1;
        samples.add(Map.of("step",tick,"temperature",temperature,"vibration",vibration,"rpm",1480+12*Math.sin(tick*.21),"alarm",alarm));
        if(samples.size()>60)samples.remove(0);
    }
    public synchronized Map<String,Object> advance(){
        if(playing){tick++;if(cooling)heat*=.65;sample();}
        return state();
    }
    public synchronized Map<String,Object> action(String name,String node,String selected){
        switch(name){
            case "reset" -> reset(selected.isEmpty()?algorithm:selected);
            case "play" -> playing=true;
            case "pause" -> playing=false;
            case "step" -> {tick++;if(cooling)heat*=.65;sample();}
            case "inject_offline","inject_driver","inject_runtime","inject_heat" -> {
                if(!fault.isEmpty())throw new IllegalArgumentException("请先重置演练，再注入另一项故障。");
                if(!name.equals("inject_heat")&&!caps.containsKey(node))throw new IllegalArgumentException("Unknown node");
                fault=name;faultNode=name.equals("inject_heat")?"motor-01":node;phase="FAULT";normalSamples=0;diagnosis.clear();moves.clear();
                if(name.equals("inject_offline"))offline.add(node);
                else if(name.equals("inject_heat")){heat=29;sample();}
                else{
                    var c=caps.get(node);
                    Set<String> drivers=new HashSet<>(c.drivers()),runtimes=new HashSet<>(c.runtimes());
                    if(name.equals("inject_driver")){
                        if(!drivers.remove("SENSOR_DRIVER")){fault="";throw new IllegalArgumentException("该节点已经没有SENSOR_DRIVER，请选择其他节点。");}
                    }else runtimes.clear();
                    caps.put(node,new PlatformPolicy.Capabilities(c.architecture(),runtimes,c.apis(),drivers,c.security()));
                }
                event("FAULT","注入故障："+fault+" @ "+faultNode+"；服务可用性按当前节点声明和依赖重新计算。");
            }
            case "diagnose" -> {
                if(fault.isEmpty())throw new IllegalArgumentException("请先注入故障。");
                if(!phase.equals("FAULT")&&!phase.equals("DIAGNOSED"))throw new IllegalArgumentException("当前阶段无需重新诊断。");
                diagnosis.clear();Set<String> available=available();
                if(fault.equals("inject_heat"))diagnosis.add(Map.of("target","motor-01","reason","TEMPERATURE_HIGH","detail","温度超过80°C；平台能力未发生变化。建议开启模拟冷却并核查连续正常采样。"));
                else for(var a:run.plan().assignments()){
                    List<String> reasons=new ArrayList<>();
                    if(offline.contains(a.node().id()))reasons.add("NODE_OFFLINE");
                    reasons.addAll(PlatformPolicy.declaredRejectionReasons(a.variant(),a.node()));
                    if(reasons.isEmpty()&&!available.contains(a.serviceId()))reasons.add("UPSTREAM_UNAVAILABLE");
                    if(!reasons.isEmpty())diagnosis.add(Map.of("target",a.serviceId()+" @ "+a.node().id(),"reason",String.join("; ",reasons),"detail","按节点状态、版本能力要求和依赖链检查；修复前不把受影响服务计为可用。"));
                }
                if(diagnosis.isEmpty())diagnosis.add(Map.of("target",faultNode,"reason","NO_ACTIVE_SERVICE_IMPACT","detail","故障存在，但当前服务没有使用缺失的能力；重新规划可保持业务，不宣称已修复该节点。"));
                phase="DIAGNOSED";event("DIAGNOSIS","已检查 "+data.services().size()+" 项服务及其依赖，诊断记录 "+diagnosis.size()+" 条。");
            }
            case "repair" -> {
                if(!phase.equals("DIAGNOSED"))throw new IllegalArgumentException("修复前请先执行诊断。");
                if(fault.equals("inject_heat")){cooling=true;phase="VERIFYING";normalSamples=0;event("COOLING","开启模拟冷却，温升逐步衰减；需至少3次连续正常采样后验证。");}
                else{
                    Map<String,String> old=new HashMap<>();for(var a:run.plan().assignments())old.put(a.serviceId(),a.node().id());
                    List<NodeSpec> healthy=data.nodes().stream().filter(n->!offline.contains(n.id())).toList();
                    PlanRuntime.Run repaired=PlanRuntime.run(data,algorithm,64,healthy,caps);
                    run=repaired;moves.clear();
                    for(var a:run.plan().assignments())if(!Objects.equals(old.get(a.serviceId()),a.node().id()))
                        moves.add(Map.of("service",a.serviceId(),"from",old.getOrDefault(a.serviceId(),"未接纳"),"to",a.node().id()));
                    phase=available().size()==data.services().size()?"VERIFYING":"DEGRADED";
                    event("REPLAN","重新调用 "+algorithm+" 与完整兼容检查，CloudSim部署完成，迁移/新增 "+moves.size()+" 项；故障节点或能力仍保持故障状态。");
                }
            }
            case "verify" -> {
                if(!Set.of("VERIFYING","DEGRADED","RECOVERED").contains(phase))throw new IllegalArgumentException("请先执行修复。");
                Set<String> ready=available();
                boolean processOk=!samples.isEmpty()&&!(boolean)samples.get(samples.size()-1).get("alarm");
                if(ready.size()!=data.services().size()){phase="DEGRADED";event("VERIFY_FAIL","仍有服务或依赖不可用，不能宣布业务恢复。");}
                else if(!processOk||(fault.equals("inject_heat")&&normalSamples<3)){phase="VERIFYING";event("VERIFY_WAIT","继续采样：需要温度/振动正常，工艺故障还需连续3次正常。");}
                else{phase="RECOVERED";event("RECOVERED","恢复检查通过：全部服务、依赖、声明与资源约束通过，工艺数据正常。仅表示本次模拟业务恢复。");}
            }
            default -> throw new IllegalArgumentException("Unknown action");
        }return state();
    }
    public synchronized Map<String,Object> state(){
        Set<String> ready=available();List<Map<String,Object>> ns=new ArrayList<>(),ss=new ArrayList<>();
        for(var n:data.nodes()){
            var c=caps.get(n.id());
            var assigned=run.plan().assignments().stream().filter(a->a.node().id().equals(n.id())).toList();
            double cpu=assigned.stream().mapToDouble(a->a.variant().cpuMips()).sum();
            long ram=assigned.stream().mapToLong(a->a.variant().memoryMiB()).sum();
            Map<String,Object> item=new LinkedHashMap<>();
            item.put("id",n.id());item.put("os",n.os().name());item.put("status",offline.contains(n.id())?"OFFLINE":(!fault.isEmpty()&&faultNode.equals(n.id())?"CAPABILITY_GAP":"ONLINE"));
            item.put("cpu",cpu);item.put("cpu_total",n.totalMips());item.put("ram",ram);item.put("ram_total",n.memoryMiB());
            item.put("architecture",c.architecture());item.put("runtimes",new TreeSet<>(c.runtimes()));item.put("drivers",new TreeSet<>(c.drivers()));ns.add(item);
        }
        for(var s:data.services()){
            var a=run.plan().assignments().stream().filter(x->x.serviceId().equals(s.id())).findFirst();
            ss.add(Map.of("id",s.id(),"stage",s.id().split("-")[0],"node",a.map(x->x.node().id()).orElse("未接纳"),"status",ready.contains(s.id())?"READY":"BLOCKED","dependencies",s.dependencies()));
        }
        Map<String,Object> result=new LinkedHashMap<>();
        result.put("session",session);result.put("algorithm",algorithm);result.put("phase",phase);result.put("playing",playing);
        result.put("tick",tick);result.put("fault",fault);result.put("fault_node",faultNode);result.put("normal_samples",normalSamples);
        result.put("ready",ready.size());result.put("requested",data.services().size());result.put("nodes",ns);result.put("services",ss);
        result.put("samples",List.copyOf(samples));result.put("history",List.copyOf(history));result.put("diagnosis",List.copyOf(diagnosis));result.put("moves",List.copyOf(moves));
        result.put("deployment_seconds",run.seconds());result.put("planning_ms",run.planningMs());result.put("deployment_events",run.events());
        return result;
    }
    public synchronized Map<String,Object> export(){
        Map<String,Object> result=new LinkedHashMap<>(state());
        result.put("plan",PlanRuntime.describe(data,run));
        result.put("notice","SYNTHETIC industrial process and capability declarations. Java planners and CloudSim deployment events execute locally; no physical device or real OS/container/RTP verification.");
        return result;
    }
}
