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
        PlatformPolicy.configureExternal("configured","full",capabilities,data.variantRequirements());
        long start=System.nanoTime();ExactPlanner.Outcome exact=null;
        Result plan;
        switch(algorithm){
            case "first_fit" -> plan=FirstFitPlanner.plan(nodes,data.services());
            case "round_robin" -> plan=RoundRobinPlanner.plan(nodes,data.services());
            case "best_fit" -> plan=BestFitPlanner.plan(nodes,data.services());
            case "beam_search" -> plan=BeamSearchPlanner.plan(nodes,data.services(),width);
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
