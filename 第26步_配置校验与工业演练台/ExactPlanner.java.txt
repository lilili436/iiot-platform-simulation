package org.example.iiot.placement;
import java.util.*;
import org.example.iiot.model.*;
import org.example.iiot.metrics.WorkflowMetrics;
import org.example.iiot.placement.FirstFitPlanner.*;

/** Independent exhaustive assignment enumerator, intended only for <=8 services. */
public final class ExactPlanner {
    public record Outcome(Result plan,boolean optimal,long visited,double seconds,int workflows,String objective){}
    private final List<NodeSpec> nodes;
    private final List<ServiceSpec> services;
    private final String objective;
    private final long limit,deadline;
    private long visited;
    private boolean exhausted=true;
    private List<Assignment> best=List.of();
    private double bestSeconds=0;
    private int bestWorkflows=0,bestActive=0;
    private ExactPlanner(List<NodeSpec> nodes,List<ServiceSpec> services,String objective,long limit,long millis){
        this.nodes=nodes;this.services=services;this.objective=objective;this.limit=limit;
        deadline=System.nanoTime()+millis*1_000_000L;
    }
    public static Outcome solve(List<NodeSpec> nodes,List<ServiceSpec> services,String objective,long limit,long millis){
        if(services.size()>8)throw new IllegalArgumentException("Exact verification supports at most 8 services");
        if(!Set.of("service_first","workflow_first").contains(objective)||limit<1||millis<1)
            throw new IllegalArgumentException("Invalid exact solver controls");
        Set<String> done=new HashSet<>();
        for(var s:services){if(!done.containsAll(s.dependencies())||!done.add(s.id()))throw new IllegalArgumentException("Exact solver needs unique topological services");}
        var search=new ExactPlanner(nodes,services,objective,limit,millis);
        search.dfs(0,new double[nodes.size()],new long[nodes.size()],new ArrayList<>(),new HashSet<>());
        Set<String> accepted=new HashSet<>();for(var a:search.best)accepted.add(a.serviceId());
        Map<String,String> rejects=new LinkedHashMap<>();
        for(var s:services)if(!accepted.contains(s.id()))rejects.put(s.id(),accepted.containsAll(s.dependencies())?"EXACT_SKIPPED":"DEPENDENCY_REJECTED");
        return new Outcome(new Result(search.best,rejects),search.exhausted,search.visited,search.bestSeconds,search.bestWorkflows,objective);
    }
    private void dfs(int position,double[] cpu,long[] ram,List<Assignment> chosen,Set<String> accepted){
        if(visited>=limit||System.nanoTime()>deadline){exhausted=false;return;}visited++;
        if(position==services.size()){
            double seconds=scheduleSeconds(chosen,services);
            int workflows=WorkflowMetrics.summarize(services,accepted).ready();
            int active=(int)chosen.stream().map(a->a.node().id()).distinct().count();
            int primary=objective.equals("workflow_first")?Integer.compare(workflows,bestWorkflows):Integer.compare(chosen.size(),best.size());
            int secondary=objective.equals("workflow_first")?Integer.compare(chosen.size(),best.size()):0;
            if(primary>0||(primary==0&&(secondary>0||(secondary==0&&(seconds<bestSeconds-1e-9||(Math.abs(seconds-bestSeconds)<1e-9&&active<bestActive)))))){
                best=List.copyOf(chosen);bestSeconds=seconds;bestWorkflows=workflows;bestActive=active;
            }return;
        }
        ServiceSpec s=services.get(position);
        if(accepted.containsAll(s.dependencies())){
            for(int j=0;j<nodes.size();j++){
                NodeSpec n=nodes.get(j);
                for(ServiceVariant v:s.variants()){
                    if(!CompatibilityChecker.canDeploy(v,n)||cpu[j]+v.cpuMips()>n.totalMips()+1e-9||ram[j]+v.memoryMiB()>n.memoryMiB())continue;
                    cpu[j]+=v.cpuMips();ram[j]+=v.memoryMiB();chosen.add(new Assignment(s.id(),v,n));accepted.add(s.id());
                    dfs(position+1,cpu,ram,chosen,accepted);
                    cpu[j]-=v.cpuMips();ram[j]-=v.memoryMiB();chosen.remove(chosen.size()-1);accepted.remove(s.id());
                    if(!exhausted)return;
                }
            }
        }
        dfs(position+1,cpu,ram,chosen,accepted);
    }
    /** Evaluates a precedence graph with service dependencies plus per-node FIFO edges.
        It does not use the beam planner's incremental nodeReady state. */
    public static double scheduleSeconds(List<Assignment> assignments,List<ServiceSpec> services){
        Map<String,Assignment> selected=new LinkedHashMap<>();for(var a:assignments)selected.put(a.serviceId(),a);
        Map<String,Set<String>> predecessors=new LinkedHashMap<>();
        for(var s:services)if(selected.containsKey(s.id()))predecessors.put(s.id(),new LinkedHashSet<>(s.dependencies()));
        Map<String,String> lastOnNode=new HashMap<>();
        for(var a:assignments){
            String previous=lastOnNode.put(a.node().id(),a.serviceId());
            if(previous!=null)predecessors.get(a.serviceId()).add(previous);
        }
        Map<String,Double> finish=new HashMap<>();
        while(finish.size()<assignments.size()){
            boolean changed=false;
            for(var e:predecessors.entrySet()){
                if(finish.containsKey(e.getKey()))continue;
                if(!selected.keySet().containsAll(e.getValue()))throw new IllegalArgumentException("Plan has missing accepted dependency");
                if(!finish.keySet().containsAll(e.getValue()))continue;
                double start=e.getValue().stream().mapToDouble(finish::get).max().orElse(0);
                Assignment a=selected.get(e.getKey());
                finish.put(e.getKey(),start+a.variant().packageMiB()/a.node().bandwidthMiBps()+a.variant().startupSeconds());
                changed=true;
            }if(!changed)throw new IllegalArgumentException("Plan FIFO/dependency cycle");
        }return finish.values().stream().mapToDouble(Double::doubleValue).max().orElse(0);
    }
}
