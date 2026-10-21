package org.example.iiot;
import java.nio.file.*;
import java.nio.charset.StandardCharsets;
import java.util.*;
import org.example.iiot.config.ScenarioLoader;
import org.example.iiot.config.ScenarioLoader.Data;
import org.example.iiot.model.*;
import org.example.iiot.metrics.WorkflowMetrics;
import org.example.iiot.placement.*;
public final class StudyMain {
 record Method(String name,String algorithm,int width){}
 static final List<Method> METHODS=List.of(new Method("first_fit","first_fit",64),new Method("round_robin","round_robin",64),
  new Method("best_fit","best_fit",64),new Method("beam_input_w64","beam_input",64),
  new Method("beam_scarcity_w4","beam_search",4),new Method("beam_scarcity_w16","beam_search",16),new Method("beam_scarcity_w64","beam_search",64));
 static Data generate(Data base,int seed,String topology,String profile,int scale){
  Random random=new Random(seed);var nodes=new ArrayList<NodeSpec>();var caps=new LinkedHashMap<>(base.nodeCapabilities());
  for(var n:base.nodes()){
   double factor=(profile.equals("ample")?1.0:.32)*(.85+.30*random.nextDouble());
   nodes.add(new NodeSpec(n.id(),n.os(),n.cpuCores(),Math.max(50,Math.rint(n.mipsPerCore()*factor)),Math.max(64,(int)(n.memoryMiB()*factor/32)*32),
    Math.max(5,Math.rint(n.bandwidthMiBps()*(.75+.5*random.nextDouble())))));
   if(profile.equals("gap")&&(n.id().endsWith("02"))){
    var c=caps.get(n.id());caps.put(n.id(),new PlatformPolicy.Capabilities(c.architecture(),Set.of(),c.apis(),c.drivers(),c.security()));
   }
  }
  int[] stages=topology.equals("chain")?new int[]{0,2,0,2}:new int[]{0,1,3,2};
  String[][] dependencies=topology.equals("chain")?new String[][]{{},{"a"},{},{"c"}}:
   topology.equals("fork_join")?new String[][]{{},{"a"},{"a"},{"b","c"}}:new String[][]{{},{},{},{}};
  var services=new ArrayList<ServiceSpec>();var requirements=new LinkedHashMap<String,PlatformPolicy.Requirements>();
  for(int i=0;i<scale;i++){
   int local=i%4;String id=""+(char)('a'+local)+"-"+(i/4);var template=base.services().get(stages[local]);var variants=new ArrayList<ServiceVariant>();
   double factor=.8+.4*random.nextDouble();
   for(var v:template.variants()){
    String vid=v.id()+"-"+id;
    variants.add(new ServiceVariant(vid,v.os(),Math.rint(v.cpuMips()*factor),Math.max(16,(int)(v.memoryMiB()*factor/16)*16),
      Math.rint(v.packageMiB()*factor*10)/10,Math.rint(v.startupSeconds()*factor*100)/100));
    requirements.put(vid,base.variantRequirements().get(v.id()));
   }
   List<String> deps=new ArrayList<>();
   if(topology.equals("random_dag")){
    for(int j=0;j<i;j++)if(random.nextDouble()<.22)deps.add(""+(char)('a'+j%4)+"-"+(j/4));
   }else for(String dependency:dependencies[local])deps.add(dependency+"-"+(i/4));
   services.add(new ServiceSpec(id,List.copyOf(deps),variants));
  }
  String id="seed"+seed+"-"+topology+"-"+profile+"-s"+scale;
  return new Data(id,nodes,services,caps,requirements,Map.of("all","SYNTHETIC fixed seeded generator v1"),Path.of("study/inputs",id+".json"));
 }
 static Map<String,Object> input(Data d,int seed,String topology,String profile,int scale){
  Map<String,Object> m=new LinkedHashMap<>();m.put("schema_version",1);m.put("scenario",d.id());m.put("seed",seed);m.put("topology",topology);m.put("profile",profile);m.put("service_scale",scale);
  m.put("nodes",d.nodes().stream().map(n->{var c=d.nodeCapabilities().get(n.id());var x=new LinkedHashMap<String,Object>();
   x.put("id",n.id());x.put("os",n.os().name());x.put("cores",n.cpuCores());x.put("mips_per_core",n.mipsPerCore());x.put("ram_mib",n.memoryMiB());x.put("bandwidth_mibps",n.bandwidthMiBps());
   x.put("architecture",c.architecture());x.put("runtimes",new TreeSet<>(c.runtimes()));x.put("apis",new TreeSet<>(c.apis()));x.put("drivers",new TreeSet<>(c.drivers()));x.put("security",new TreeSet<>(c.security()));return x;}).toList());
  m.put("services",d.services().stream().map(s->Map.of("id",s.id(),"dependencies",s.dependencies(),"variants",s.variants().stream().map(v->{
   var r=d.variantRequirements().get(v.id());Map<String,Object>x=new LinkedHashMap<>();x.put("id",v.id());x.put("os",v.os().name());x.put("cpu_mips",v.cpuMips());x.put("ram_mib",v.memoryMiB());x.put("package_mib",v.packageMiB());x.put("startup_s",v.startupSeconds());
   x.put("architecture",r.architecture());x.put("runtime",r.runtime());x.put("apis",new TreeSet<>(r.apis()));x.put("drivers",new TreeSet<>(r.drivers()));x.put("security",new TreeSet<>(r.security()));return x;}).toList())).toList());
  return m;
 }
 public static void main(String[]args)throws Exception{
  int repeats=args.length==0?3:Integer.parseInt(args[0]);if(repeats<2||repeats>20)throw new IllegalArgumentException("Use 2..20 measured repetitions");
  var base=ScenarioLoader.load(Path.of("configs/demo-industrial"));
  Path root=Path.of("study");Files.createDirectories(root.resolve("inputs"));
  var results=new ArrayList<Map<String,Object>>();var exactRows=new ArrayList<Map<String,Object>>();
  int pairedCases=0,measured=0;
  for(int seed:List.of(11,29,47,83,101))for(String topology:List.of("chain","fork_join","independent","random_dag"))for(String profile:List.of("ample","pressure","gap"))for(int scale:List.of(4,8,12)){
   var d=generate(base,seed,topology,profile,scale);pairedCases++;
   Files.writeString(d.source(),Json.write(input(d,seed,topology,profile,scale)),StandardCharsets.UTF_8);
   for(String objective:List.of("service_first","workflow_first")){
    PlatformPolicy.configureExternal("study","full",d.nodeCapabilities(),d.variantRequirements());
    var exact=scale<=8?ExactPlanner.solve(d.nodes(),d.services(),objective,scale<=4?500000:100000,scale<=4?2000:250):null;
    Map<String,Object> ex=new LinkedHashMap<>();ex.put("scenario",d.id());ex.put("objective",objective);ex.put("optimal",(exact!=null&&exact.optimal()));ex.put("visited",exact==null?0:exact.visited());ex.put("service_scale",scale);ex.put("skip_reason",exact==null?"more_than_8_services":"");
    ex.put("services",exact==null?null:exact.plan().assignments().size());ex.put("workflows",exact==null?null:exact.workflows());ex.put("seconds",exact==null?null:exact.seconds());exactRows.add(ex);
    for(var method:METHODS){
     // One unmeasured warm-up per same-input method/objective; one JVM for the study.
     PlanRuntime.run(d,method.algorithm(),method.width(),d.nodes(),d.nodeCapabilities(),objective);
     String reference=null;
     for(int repeat=1;repeat<=repeats;repeat++){
      var run=PlanRuntime.run(d,method.algorithm(),method.width(),d.nodes(),d.nodeCapabilities(),objective);
      String signature=run.plan().assignments().stream().map(a->a.serviceId()+"@"+a.node().id()+"/"+a.variant().id()).reduce("",(a,b)->a+";"+b)+run.plan().rejections();
      if(reference!=null&&!reference.equals(signature))throw new AssertionError("Non-deterministic assignment");reference=signature;
      if(Math.abs(run.seconds()-run.predicted())>1e-7)throw new AssertionError("Independent FIFO time mismatch");
      var workflows=WorkflowMetrics.summarize(d.services(),run.ready());
      double cpu=run.plan().assignments().stream().mapToDouble(a->a.variant().cpuMips()).sum()/d.nodes().stream().mapToDouble(NodeSpec::totalMips).sum();
      double ram=run.plan().assignments().stream().mapToDouble(a->a.variant().memoryMiB()).sum()/d.nodes().stream().mapToDouble(NodeSpec::memoryMiB).sum();
      var row=new LinkedHashMap<String,Object>();row.put("scenario",d.id());row.put("seed",seed);row.put("topology",topology);row.put("profile",profile);
      row.put("objective",objective);row.put("method",method.name());row.put("width",method.width());row.put("repeat",repeat);
      row.put("requested",scale);row.put("service_scale",scale);row.put("ready",run.ready().size());row.put("workflows",workflows.ready());row.put("workflows_requested",workflows.requested());
      row.put("ready_service_ids",new TreeSet<>(run.ready()));row.put("seconds",run.seconds());row.put("planning_ms",run.planningMs());row.put("cpu_reserved",cpu);row.put("ram_reserved",ram);
      row.put("plan",PlanRuntime.describe(d,run));row.put("exact_proven",(exact!=null&&exact.optimal()));
      boolean sameOrder=run.plan().assignments().stream().map(a->a.serviceId()).toList().equals(d.services().stream().map(ServiceSpec::id).filter(run.ready()::contains).toList());
      row.put("exact_same_fifo_order",sameOrder);
      if((exact!=null&&exact.optimal())&&sameOrder){
       int gap=objective.equals("workflow_first")?exact.workflows()-workflows.ready():exact.plan().assignments().size()-run.ready().size();
       if(gap<0)throw new AssertionError("Heuristic exceeded proven same-order objective");
       row.put("primary_gap",gap);
      }else row.put("primary_gap",null);
      results.add(row);measured++;
     }
    }
   }
   System.out.println("STUDY "+pairedCases+"/180 "+d.id());
  }
  var manifest=new LinkedHashMap<String,Object>();manifest.put("schema_version",1);manifest.put("scenario_count",pairedCases);manifest.put("measured_runs",measured);manifest.put("measured_repetitions",repeats);
  manifest.put("warmup_runs",pairedCases*2*METHODS.size());manifest.put("seeds",List.of(11,29,47,83,101));
  manifest.put("notice","SYNTHETIC seeded scenarios. Same-input repeats measure JVM timing variability, not independent scenario samples. Exact gaps only when exhaustive and FIFO order identical. No universal optimality claim.");
  Files.writeString(root.resolve("manifest.json"),Json.write(manifest),StandardCharsets.UTF_8);
  Files.writeString(root.resolve("results.json"),Json.write(results),StandardCharsets.UTF_8);
  Files.writeString(root.resolve("exact.json"),Json.write(exactRows),StandardCharsets.UTF_8);
  System.out.println("COMPLETE "+measured+" measured runs; "+pairedCases+" seeded paired scenarios");
 }
}
