package org.example.iiot;
import java.nio.file.*;
import java.nio.charset.StandardCharsets;
import java.util.*;
import org.example.iiot.config.ScenarioLoader;
import org.example.iiot.demo.DemoEngine;
import org.example.iiot.placement.*;
public final class FinalCheckMain {
 static int checks=0;
 static void ok(boolean b,String m){checks++;if(!b)throw new AssertionError(m);}
 @SuppressWarnings("unchecked") static List<Map<String,Object>> rows(Map<String,Object>s,String key){return (List<Map<String,Object>>)s.get(key);}
 static Map<String,Object> node(Map<String,Object>s,String id){return rows(s,"nodes").stream().filter(n->n.get("id").equals(id)).findFirst().orElseThrow();}
 static Map<String,String> places(Map<String,Object>s){var r=new TreeMap<String,String>();for(var a:rows(s,"services"))r.put(a.get("id").toString(),a.get("node").toString());return r;}
 public static void main(String[]args)throws Exception{
  var d=ScenarioLoader.load(Path.of("configs/demo-industrial"));
  var e=new DemoEngine(d,Path.of("verification/final-events.jsonl"));e.action("pause","","");
  for(String objective:List.of("service_first","workflow_first")){
   e.action("reset","","beam_search",objective,"AUTO");
   for(String platform:List.of("WINDOWS","LINUX","VXWORKS")){
    for(String fault:List.of("inject_offline","inject_driver","inject_runtime")){
     e.action("reset","","beam_search",objective,platform); String target=places(e.state()).get("collect-c1");
     e.action("settings","","","",platform);
     var before=e.state();var s=e.action(fault,target,"");
     ok((int)s.get("ready")==4,"all four ready in forced takeover");
     var baseDetect=places(before).get("detect-c1");
     ok(places(s).get("detect-c1").equals(baseDetect),"healthy detect pinned");
     var moved=rows(s,"moves");ok(!moved.isEmpty(),"real migration");
     for(var m:moved){var n=node(s,m.get("to").toString());ok(n.get("os").equals(platform),"requested platform honored");}
     var taken=places(s);var events=Json.write(s.get("deployment_events"));
     e.action("diagnose","","");s=e.action("repair","","");
     ok(node(s,target).get("status").equals("ONLINE")&&node(s,target).get("role").equals("STANDBY"),"repaired online spare");
     ok(places(s).equals(taken),"repair no failback");
     ok(events.equals(Json.write(s.get("deployment_events"))),"repair no redeployment");
     s=e.action("verify","","");ok(s.get("phase").equals("RECOVERED"),"verified");
    }
   }
  }
  // A detect service has no VX version; forcing VX cannot mutate the session.
  e.action("reset","","beam_search","workflow_first","VXWORKS");
  var before=e.state();String detect=places(before).get("detect-c1");boolean rejected=false;
  try{e.action("inject_runtime",detect,"");}catch(IllegalArgumentException expected){rejected=true;}
  ok(rejected,"incompatible forced target rejected");
  ok(Json.write(before).equals(Json.write(e.state())),"failed injection atomic");
  e.action("settings","","","","WINDOWS");e.action("inject_runtime",detect,"");e.action("diagnose","","");
  var s=e.action("repair","","");ok(node(s,detect).get("role").equals("STANDBY"),"repaired detect node spare");
  s=e.action("verify","","");ok((int)s.get("ready")==4,"windows detect takeover works");
  var p=ScenarioLoader.load(Path.of("configs/objective-conflict"));
  for(String objective:List.of("service_first","workflow_first")){
   PlatformPolicy.configureExternal("test","full",p.nodeCapabilities(),p.variantRequirements());
   var beam=ObjectiveBeamPlanner.plan(p.nodes(),p.services(),256,objective,false);
   var exact=ExactPlanner.solve(p.nodes(),p.services(),objective,2000000,10000);
   ok(exact.optimal(),"counterexample exhaustively proven");
   ok(beam.assignments().size()==exact.plan().assignments().size(),"beam same objective service score");
   var ids=beam.assignments().stream().map(a->a.serviceId()).collect(java.util.stream.Collectors.toSet());
   var workflows=org.example.iiot.metrics.WorkflowMetrics.summarize(p.services(),ids).ready();
   ok(workflows==exact.workflows(),"beam same objective complete-workflow score");
   ok(objective.equals("service_first")?beam.assignments().size()==3&&workflows==0:beam.assignments().size()==1&&workflows==1,"objective conflict preserved");
  }
  for(String o:List.of("service_first","workflow_first")){
   for(String a:List.of("beam_input","beam_search")){
    var x=PlanRuntime.run(d,a,64,d.nodes(),d.nodeCapabilities(),o);
    ok(x.ready().size()==4,"both objective and ordering modes execute");
   }
  }
  var out=Map.of("status","PASS","checks",checks,"scope","forced Linux/Windows/VxWorks takeover; node reuse; no failback; atomic incompatible rejection; exact objective counterexample");
  Files.createDirectories(Path.of("verification"));
  Files.writeString(Path.of("verification/final-checks.json"),Json.write(out),StandardCharsets.UTF_8);
  System.out.println("PASS "+checks+" final integration checks");
 }
}
