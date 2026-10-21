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
    private PlanRuntime.Run run,beforeFault;
    private String algorithm="beam_search",phase="RUNNING",fault="",faultNode="";
    private boolean playing=true,cooling=false;
    private int tick=0,normalSamples=0;
    private double heat=0;
    private int episode=0,episodeStarted=0;
    private final Set<String> completedFaults=new LinkedHashSet<>();
    private final List<Map<String,Object>> completedEpisodes=new ArrayList<>();
    private boolean canInject(){return phase.equals("RUNNING")||phase.equals("RECOVERED");}
    private final List<Map<String,Object>> samples=new ArrayList<>(),history=new ArrayList<>(),diagnosis=new ArrayList<>(),moves=new ArrayList<>();
    public DemoEngine(Data data,Path journal)throws IOException{this.data=data;this.journal=journal;Files.createDirectories(journal.toAbsolutePath().getParent());reset("beam_search");}
    private void event(String kind,String text){
        Map<String,Object> e=Map.of("step",tick,"episode",episode,"kind",kind,"text",text);
        history.add(e);
        if(history.size()>120)history.remove(0);
        try{Files.writeString(journal,Json.write(Map.of("session",session,"step",tick,"episode",episode,"kind",kind,"text",text))+"\n",StandardCharsets.UTF_8,StandardOpenOption.CREATE,StandardOpenOption.APPEND);}
        catch(IOException ex){throw new IllegalStateException("Cannot persist demo journal",ex);}
    }
    private void reset(String selected){
        if(!Set.of("beam_search","first_fit","round_robin","best_fit").contains(selected))throw new IllegalArgumentException("Invalid algorithm");
        algorithm=selected;offline.clear();caps=new LinkedHashMap<>(data.nodeCapabilities());fault="";faultNode="";heat=0;cooling=false;
        episode=0;episodeStarted=0;completedFaults.clear();completedEpisodes.clear();
        tick=0;normalSamples=0;phase="RUNNING";playing=true;samples.clear();diagnosis.clear();moves.clear();history.clear();
        run=PlanRuntime.run(data,algorithm,64,data.nodes(),caps);
        beforeFault=run;
        sample();event("READY","初始化完成：Java规划与CloudSim部署事件已执行；当前为合成工业环境。");
    }
    private Set<String> available(){return available(run);}
    private Set<String> available(PlanRuntime.Run deployment){
        PlatformPolicy.configureExternal("demo","full",caps,data.variantRequirements());
        Set<String> local=new HashSet<>();
        for(var a:deployment.plan().assignments())if(!offline.contains(a.node().id())&&
            PlatformPolicy.declaredRejectionReasons(a.variant(),a.node()).isEmpty()&&deployment.ready().contains(a.serviceId()))local.add(a.serviceId());
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
                if(!canInject())throw new IllegalArgumentException("请先修复当前故障并通过恢复验证，再注入下一项；也可以重置环境。");
                if(!name.equals("inject_heat")){
                    if(!caps.containsKey(node))throw new IllegalArgumentException("Unknown node");
                    if(offline.contains(node))throw new IllegalArgumentException("该节点已离线，请选择在线节点或重置环境。");
                    var c=caps.get(node);
                    if(name.equals("inject_driver")&&!c.drivers().contains("SENSOR_DRIVER"))
                        throw new IllegalArgumentException("该节点已经缺少SENSOR_DRIVER，请选择其他节点或重置环境。");
                    if(name.equals("inject_runtime")&&c.runtimes().isEmpty())
                        throw new IllegalArgumentException("该节点运行环境已不可用，请选择其他节点或重置环境。");
                }
                // Compute failover before committing the next episode.
                Set<String> failedOffline=new HashSet<>(offline);
                Map<String,PlatformPolicy.Capabilities> failedCaps=new LinkedHashMap<>(caps);
                PlanRuntime.Run takeover=run;
                if(name.equals("inject_offline"))failedOffline.add(node);
                else if(!name.equals("inject_heat")){
                    var c=failedCaps.get(node);
                    Set<String> drivers=new HashSet<>(c.drivers()),runtimes=new HashSet<>(c.runtimes());
                    if(name.equals("inject_driver"))drivers.remove("SENSOR_DRIVER");else runtimes.clear();
                    failedCaps.put(node,new PlatformPolicy.Capabilities(c.architecture(),runtimes,c.apis(),drivers,c.security()));
                }
                if(!name.equals("inject_heat")){
                    Set<String> excluded=new HashSet<>(failedOffline);excluded.add(node);
                    takeover=PlanRuntime.failover(data,run,excluded,failedCaps);
                }
                episode++;episodeStarted=tick;beforeFault=run;
                fault=name;faultNode=name.equals("inject_heat")?"motor-01":node;
                phase="FAULT";normalSamples=0;diagnosis.clear();moves.clear();
                offline.clear();offline.addAll(failedOffline);caps=failedCaps;run=takeover;
                if(name.equals("inject_heat")){heat=29;cooling=false;sample();}
                event("FAULT","注入故障："+fault+" @ "+faultNode+"；记录原部署的故障原因与依赖影响。");
                if(!name.equals("inject_heat")){
                    Map<String,String> old=new HashMap<>();
                    for(var a:beforeFault.plan().assignments())old.put(a.serviceId(),a.node().id());
                    for(var a:run.plan().assignments())if(!Objects.equals(old.get(a.serviceId()),a.node().id()))
                        moves.add(Map.of("service",a.serviceId(),"from",old.getOrDefault(a.serviceId(),"未接纳"),"to",a.node().id()));
                    event("FAILOVER","自动启动兼容备用节点接管；健康节点原部署保留，迁移/新增 "+moves.size()+" 项，当前可用 "+available().size()+"/"+data.services().size()+"。故障节点修复后不自动回迁。");
                    if(!run.plan().rejections().isEmpty())
                        event("STANDBY_INSUFFICIENT","备用资源或兼容能力不足："+run.plan().rejections()+"；保留业务未恢复状态。");
                }
            }
            case "diagnose" -> {
                if(fault.isEmpty())throw new IllegalArgumentException("请先注入故障。");
                if(!phase.equals("FAULT")&&!phase.equals("DIAGNOSED"))throw new IllegalArgumentException("当前阶段无需重新诊断。");
                diagnosis.clear();Set<String> available=available(beforeFault);
                if(fault.equals("inject_heat"))diagnosis.add(Map.of("target","motor-01","reason","TEMPERATURE_HIGH","detail","温度超过80°C；平台能力未发生变化。建议开启模拟冷却并核查连续正常采样。"));
                else for(var a:beforeFault.plan().assignments()){
                    List<String> reasons=new ArrayList<>();
                    if(offline.contains(a.node().id()))reasons.add("NODE_OFFLINE");
                    reasons.addAll(PlatformPolicy.declaredRejectionReasons(a.variant(),a.node()));
                    if(reasons.isEmpty()&&!available.contains(a.serviceId()))reasons.add("UPSTREAM_UNAVAILABLE");
                    if(!reasons.isEmpty())diagnosis.add(Map.of("target",a.serviceId()+" @ "+a.node().id(),"reason",String.join("; ",reasons),"detail","原部署在注入时受到影响；已触发备用接管，当前该服务"+(available().contains(a.serviceId())?"已在接管部署中可用。":"仍受阻，备用条件不足。")));
                }
                if(diagnosis.isEmpty())diagnosis.add(Map.of("target",faultNode,"reason","NO_ACTIVE_SERVICE_IMPACT","detail","该故障节点原来未承载受影响服务，无需迁移；修复后恢复在线备用。"));
                if(!fault.equals("inject_heat")){
                    diagnosis.add(Map.of("target",faultNode,"reason",fault.equals("inject_offline")?"NODE_OFFLINE":fault.equals("inject_driver")?"DRIVER_MISSING":"RUNTIME_UNSUPPORTED",
                        "detail","故障节点暂停承载业务；修复节点本身后保持现有接管部署，不自动回迁。"));
                    for(var rejected:run.plan().rejections().entrySet())
                        diagnosis.add(Map.of("target",rejected.getKey(),"reason",rejected.getValue(),"detail","当前备用部署未接纳此服务；不会把部分接管标记为全部恢复。"));
                }
                phase="DIAGNOSED";event("DIAGNOSIS","已检查 "+data.services().size()+" 项服务及其依赖，诊断记录 "+diagnosis.size()+" 条。");
            }
            case "repair" -> {
                if(!phase.equals("DIAGNOSED"))throw new IllegalArgumentException("修复前请先执行诊断。");
                if(fault.equals("inject_heat")){cooling=true;phase="VERIFYING";normalSamples=0;event("COOLING","开启模拟冷却，温升逐步衰减；需至少3次连续正常采样后验证。");}
                else{
                    Map<String,PlatformPolicy.Capabilities> restoredCaps=new LinkedHashMap<>(caps);
                    restoredCaps.put(faultNode,data.nodeCapabilities().get(faultNode));
                    PlatformPolicy.configureExternal("repaired","full",restoredCaps,data.variantRequirements());
                    PlanRuntime.validate(data.services(),data.nodes(),run.plan());
                    offline.remove(faultNode);caps=restoredCaps;
                    event("NODE_REPAIRED","节点 "+faultNode+" 已恢复在线并作为备用；当前接管部署保留，不自动回迁，可再次注入故障。");
                    phase=available().size()==data.services().size()?"VERIFYING":"DEGRADED";
                    if(phase.equals("DEGRADED"))
                        event("VERIFY_PENDING","节点已修复，但备用接管仍不完整。请检查资源/兼容条件或重置环境；不将节点修复等同于全部业务恢复。");
                }
            }
            case "verify" -> {
                if(!Set.of("VERIFYING","DEGRADED","RECOVERED").contains(phase))throw new IllegalArgumentException("请先执行修复。");
                if(phase.equals("RECOVERED"))return state();
                Set<String> ready=available();
                boolean processOk=!samples.isEmpty()&&!(boolean)samples.get(samples.size()-1).get("alarm");
                boolean targetOk=fault.equals("inject_heat")||(!offline.contains(faultNode)&&
                    Objects.equals(caps.get(faultNode),data.nodeCapabilities().get(faultNode)));
                if(!targetOk){phase="DEGRADED";event("VERIFY_FAIL","目标节点或能力尚未恢复，不能宣布修复成功。");}
                else if(ready.size()!=data.services().size()){phase="DEGRADED";event("VERIFY_FAIL","仍有服务或依赖不可用，不能宣布业务恢复。");}
                else if(!processOk||(fault.equals("inject_heat")&&normalSamples<3)){phase="VERIFYING";event("VERIFY_WAIT","继续采样：需要温度/振动正常，工艺故障还需连续3次正常。");}
                else{
                    phase="RECOVERED";completedFaults.add(fault);
                    completedEpisodes.add(Map.of("episode",episode,"fault",fault,"node",faultNode,
                        "started_step",episodeStarted,"finished_step",tick,
                        "diagnosis",List.copyOf(diagnosis),"moves",List.copyOf(moves),
                        "deployment_events",run.events()));
                    event("RECOVERED","本轮恢复检查通过：全部服务、依赖、声明与资源约束通过，工艺数据正常。可直接继续注入下一项故障，或选择重置环境。");
                }
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
            item.put("id",n.id());item.put("os",n.os().name());item.put("status",offline.contains(n.id())?"OFFLINE":(!c.equals(data.nodeCapabilities().get(n.id()))?"CAPABILITY_GAP":"ONLINE"));
            item.put("role",assigned.isEmpty()?"STANDBY":"ACTIVE");
            item.put("cpu",cpu);item.put("cpu_total",n.totalMips());item.put("ram",ram);item.put("ram_total",n.memoryMiB());
            item.put("architecture",c.architecture());item.put("runtimes",new TreeSet<>(c.runtimes()));item.put("drivers",new TreeSet<>(c.drivers()));ns.add(item);
        }
        for(var s:data.services()){
            var a=run.plan().assignments().stream().filter(x->x.serviceId().equals(s.id())).findFirst();
            ss.add(Map.of("id",s.id(),"stage",s.id().split("-")[0],"node",a.map(x->x.node().id()).orElse("未接纳"),"status",ready.contains(s.id())?"READY":"BLOCKED","dependencies",s.dependencies()));
        }
        Map<String,Object> result=new LinkedHashMap<>();
        result.put("session",session);result.put("algorithm",algorithm);result.put("phase",phase);result.put("playing",playing);
        result.put("can_inject",canInject());result.put("episode",episode);
        result.put("completed_faults",List.copyOf(completedFaults));result.put("completed_episodes",List.copyOf(completedEpisodes));
        result.put("cooling_active",cooling);
        result.put("failover_policy","PIN_HEALTHY_PREFER_STANDBY_NO_FAILBACK");
        result.put("standby_shortage",!run.plan().rejections().isEmpty());
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
