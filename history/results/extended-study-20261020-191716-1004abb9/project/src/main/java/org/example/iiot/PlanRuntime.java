package org.example.iiot;
import java.util.*;
import org.cloudbus.cloudsim.core.CloudSim;
import org.example.iiot.config.ScenarioLoader.Data;
import org.example.iiot.model.*;
import org.example.iiot.metrics.WorkflowMetrics;
import org.example.iiot.placement.*;
import org.example.iiot.placement.FirstFitPlanner.*;
import org.example.iiot.simulation.DeploymentSimulation;

public final class PlanRuntime {
    private PlanRuntime(){}
    public record Run(Result plan,Set<String> ready,double seconds,List<Map<String,Object>> events,
        boolean exact,boolean optimal,long visited,double predicted,double planningMs){}
    public static synchronized Run run(Data data,String algorithm,int width,List<NodeSpec> nodes,
            Map<String,PlatformPolicy.Capabilities> capabilities){
        return run(data,algorithm,width,nodes,capabilities,"legacy");
    }
    public static synchronized Run run(Data data,String algorithm,int width,List<NodeSpec> nodes,
            Map<String,PlatformPolicy.Capabilities> capabilities,String objective){
        if(!Set.of("legacy","service_first","workflow_first").contains(objective))throw new IllegalArgumentException("Invalid objective");
        PlatformPolicy.configureExternal("configured","full",capabilities,data.variantRequirements());
        long start=System.nanoTime();ExactPlanner.Outcome exact=null;
        Result plan;
        switch(algorithm){
            case "first_fit" -> plan=FirstFitPlanner.plan(nodes,data.services());
            case "round_robin" -> plan=RoundRobinPlanner.plan(nodes,data.services());
            case "best_fit" -> plan=BestFitPlanner.plan(nodes,data.services());
            case "beam_search" -> plan=objective.equals("legacy")?BeamSearchPlanner.plan(nodes,data.services(),width):ObjectiveBeamPlanner.plan(nodes,data.services(),width,objective,true);
            case "beam_input" -> plan=ObjectiveBeamPlanner.plan(nodes,data.services(),width,objective.equals("legacy")?"service_first":objective,false);
            case "exact_service","exact_workflow" -> {
                exact=ExactPlanner.solve(nodes,data.services(),algorithm.equals("exact_service")?"service_first":"workflow_first",2_000_000,10_000);
                plan=exact.plan();
            }
            default -> throw new IllegalArgumentException("Unknown algorithm "+algorithm);
        }
        double planning=(System.nanoTime()-start)/1e6;
        validate(data.services(),nodes,plan);
        double predicted=ExactPlanner.scheduleSeconds(plan.assignments(),data.services());
        CloudSim.init(1,Calendar.getInstance(),false);
        var deployment=new DeploymentSimulation("Deployment",data.services(),plan);
        CloudSim.startSimulation();
        if(deployment.readyCount()!=plan.assignments().size())throw new IllegalStateException("Accepted services failed to reach READY");
        // CloudSim's event quantum may round very short delays; benchmark configs avoid this.
        return new Run(plan,deployment.readyServiceIds(),deployment.deploymentSeconds(),deployment.events(),
            exact!=null,exact!=null&&exact.optimal(),exact==null?0:exact.visited(),predicted,planning);
    }
    private record Placement(List<Assignment> assignments,Map<String,String> rejected,double cost){}
    /**
     * Bounded standby search, independent of the initial-placement algorithm.
     * Healthy assignments are pinned. Reserve their capacity before allocating
     * evacuated services so an earlier service cannot steal a later pin's budget.
     */
    public static synchronized Run failover(Data data,Run previous,Set<String> excluded,
            Map<String,PlatformPolicy.Capabilities> capabilities) {
        return failover(data,previous,excluded,capabilities,"AUTO","service_first");
    }
    public static synchronized Run failover(Data data,Run previous,Set<String> excluded,
            Map<String,PlatformPolicy.Capabilities> capabilities,String targetPlatform,String objective){
        if(!Set.of("AUTO","LINUX","WINDOWS","VXWORKS").contains(targetPlatform))throw new IllegalArgumentException("Invalid takeover platform");
        if(!Set.of("service_first","workflow_first").contains(objective))throw new IllegalArgumentException("Invalid objective");
        PlatformPolicy.configureExternal("standby","full",capabilities,data.variantRequirements());
        long started=System.nanoTime();
        List<NodeSpec> nodes=data.nodes().stream().filter(n->!excluded.contains(n.id())).toList();
        Map<String,Assignment> prior=new LinkedHashMap<>(),pins=new LinkedHashMap<>();
        Set<String> active=new HashSet<>();
        for(var a:previous.plan().assignments()){
            prior.put(a.serviceId(),a);active.add(a.node().id());
            if(nodes.contains(a.node())&&CompatibilityChecker.canDeploy(a.variant(),a.node()))pins.put(a.serviceId(),a);
        }
        Map<String,Double> fixedCpu=new HashMap<>();Map<String,Long> fixedRam=new HashMap<>();
        for(var a:pins.values()){
            fixedCpu.merge(a.node().id(),a.variant().cpuMips(),Double::sum);
            fixedRam.merge(a.node().id(),(long)a.variant().memoryMiB(),Long::sum);
        }
        Comparator<Placement> ranking=Comparator.<Placement>comparingInt(p->-p.assignments().size())
            .thenComparingDouble(Placement::cost);
        if(objective.equals("workflow_first"))ranking=Comparator.<Placement>comparingInt(p->-WorkflowMetrics.summarize(data.services(),
            p.assignments().stream().map(Assignment::serviceId).collect(java.util.stream.Collectors.toSet())).ready()).thenComparing(ranking);
        List<Placement> beam=new ArrayList<>();beam.add(new Placement(List.of(),Map.of(),0));
        long visited=0;
        for(var service:data.services()){
            List<Placement> next=new ArrayList<>();
            for(var partial:beam){
                Set<String> accepted=new HashSet<>();
                for(var a:partial.assignments())accepted.add(a.serviceId());
                if(!accepted.containsAll(service.dependencies())){
                    Map<String,String> rejected=new LinkedHashMap<>(partial.rejected());
                    rejected.put(service.id(),"DEPENDENCY_REJECTED");
                    next.add(new Placement(partial.assignments(),rejected,partial.cost()));continue;
                }
                var pin=pins.get(service.id());
                if(pin!=null){
                    List<Assignment> assignments=new ArrayList<>(partial.assignments());assignments.add(pin);
                    next.add(new Placement(assignments,partial.rejected(),partial.cost()));continue;
                }
                for(var node:nodes)for(var variant:service.variants()){
                    visited++;
                    if(!targetPlatform.equals("AUTO")&&!node.os().name().equals(targetPlatform))continue;
                    if(!CompatibilityChecker.canDeploy(variant,node))continue;
                    double cpu=fixedCpu.getOrDefault(node.id(),0.0);
                    long ram=fixedRam.getOrDefault(node.id(),0L);
                    for(var a:partial.assignments())if(a.node().id().equals(node.id())&&!pins.containsKey(a.serviceId())){
                        cpu+=a.variant().cpuMips();ram+=a.variant().memoryMiB();
                    }
                    if(cpu+variant.cpuMips()>node.totalMips()+1e-8||ram+variant.memoryMiB()>node.memoryMiB())continue;
                    var old=prior.get(service.id());
                    // Prefer idle standby nodes and the same OS/variant family.
                    double cost=(active.contains(node.id())?100:0)
                        +(old!=null&&old.node().os()!=node.os()?1000:0)
                        +variant.packageMiB()/node.bandwidthMiBps()+variant.startupSeconds();
                    List<Assignment> assignments=new ArrayList<>(partial.assignments());
                    assignments.add(new Assignment(service.id(),variant,node));
                    next.add(new Placement(assignments,partial.rejected(),partial.cost()+cost));
                }
                Map<String,String> rejected=new LinkedHashMap<>(partial.rejected());
                rejected.put(service.id(),"NO_FEASIBLE_STANDBY");
                next.add(new Placement(partial.assignments(),rejected,partial.cost()));
            }
            next.sort(ranking);beam=new ArrayList<>(next.subList(0,Math.min(64,next.size())));
        }
        beam.sort(ranking);var best=beam.get(0);
        Result plan=new Result(List.copyOf(best.assignments()),Map.copyOf(best.rejected()));
        validate(data.services(),nodes,plan);
        Set<String> retained=new HashSet<>();
        for(var a:plan.assignments())if(a.equals(prior.get(a.serviceId())))retained.add(a.serviceId());
        double planning=(System.nanoTime()-started)/1e6;
        CloudSim.init(1,Calendar.getInstance(),false);
        var deployment=new DeploymentSimulation("StandbyDeployment",data.services(),plan,retained);
        CloudSim.startSimulation();
        if(deployment.readyCount()!=plan.assignments().size())throw new IllegalStateException("Standby deployment incomplete");
        return new Run(plan,deployment.readyServiceIds(),deployment.deploymentSeconds(),deployment.events(),
            false,false,visited,ExactPlanner.scheduleSeconds(plan.assignments(),data.services()),planning);
    }
    public static void validate(List<ServiceSpec> services,List<NodeSpec> nodes,Result plan){
        Map<String,ServiceSpec> all=new HashMap<>();for(var s:services)all.put(s.id(),s);
        Set<String> seen=new HashSet<>();Map<String,Double> cpu=new HashMap<>();Map<String,Long> ram=new HashMap<>();
        for(var a:plan.assignments()){
            var s=all.get(a.serviceId());
            if(s==null||!seen.add(a.serviceId())||!s.variants().contains(a.variant())||!nodes.contains(a.node()))
                throw new IllegalStateException("Invalid assignment identity");
            if(!seen.containsAll(s.dependencies()))throw new IllegalStateException("Unaccepted or late dependency");
            if(!CompatibilityChecker.canDeploy(a.variant(),a.node()))throw new IllegalStateException("Incompatible assignment");
            double c=cpu.merge(a.node().id(),a.variant().cpuMips(),Double::sum);
            long m=ram.merge(a.node().id(),(long)a.variant().memoryMiB(),Long::sum);
            if(c>a.node().totalMips()+1e-8||m>a.node().memoryMiB())throw new IllegalStateException("Cumulative resource overflow");
        }
        if(!Collections.disjoint(seen,plan.rejections().keySet())||seen.size()+plan.rejections().size()!=services.size()||
            !all.keySet().containsAll(plan.rejections().keySet()))throw new IllegalStateException("Incomplete plan accounting");
    }
    public static Map<String,Object> describe(Data data,Run run){
        Map<String,Object> m=new LinkedHashMap<>();
        m.put("scenario_id",data.id());m.put("requested",data.services().size());m.put("ready",run.ready().size());
        var counts=WorkflowMetrics.summarize(data.services(),run.ready());
        m.put("workflow_requested",counts.requested());m.put("workflow_ready",counts.ready());
        m.put("deployment_seconds",run.seconds());m.put("predicted_seconds",run.predicted());m.put("planning_ms",run.planningMs());
        m.put("exact",run.exact());m.put("optimal",run.optimal());m.put("visited",run.visited());
        m.put("assignments",run.plan().assignments().stream().map(a->Map.of("service",a.serviceId(),"variant",a.variant().id(),"node",a.node().id(),"cpu",a.variant().cpuMips(),"ram",a.variant().memoryMiB())).toList());
        m.put("rejections",run.plan().rejections());m.put("events",run.events());m.put("origins",data.origins());
        return m;
    }
}
