import java.nio.file.*;
import java.nio.charset.StandardCharsets;
import java.util.*;
import org.example.iiot.demo.DemoEngine;
import org.example.iiot.config.ScenarioLoader;
import org.example.iiot.Json;

public class ContinuousCheck {
    static int assertions;
    static List<Map<String,Object>> evidence=new ArrayList<>();
    static void check(boolean yes,String name){assertions++;if(!yes)throw new AssertionError(name);}
    @SuppressWarnings("unchecked") static List<Map<String,Object>> list(Map<String,Object>s,String key){return (List<Map<String,Object>>)s.get(key);}
    static Map<String,Object> node(Map<String,Object>s,String id){return list(s,"nodes").stream().filter(n->n.get("id").equals(id)).findFirst().orElseThrow();}
    static void rejected(DemoEngine e,String action,String id){
        var before=e.state();boolean no=false;try{e.action(action,id,"");}catch(IllegalArgumentException expected){no=true;}
        check(no,"reject overlapping fault or invalid order");
        check(Json.write(before).equals(Json.write(e.state())),"failed action is atomic");
    }
    static Map<String,Object> round(DemoEngine engine,String type,String id,int number)throws Exception{
        var state=engine.state();
        check((boolean)state.get("can_inject"),"new episode allowed");
        if(!type.equals("inject_heat"))check(node(state,id).get("status").equals("ONLINE"),"target is online, including previously repaired targets");
        state=engine.action(type,id,"");
        check(state.get("phase").equals("FAULT"),"fault injected");
        if(!type.equals("inject_heat")){
            check(node(state,id).get("status").equals(type.equals("inject_offline")?"OFFLINE":"CAPABILITY_GAP"),"real failure is visible");
            if(type.equals("inject_driver"))check(!((Collection<?>)node(state,id).get("drivers")).contains("SENSOR_DRIVER"),"driver actually removed");
            if(type.equals("inject_runtime"))check(((Collection<?>)node(state,id).get("runtimes")).isEmpty(),"runtime actually removed");
        }
        rejected(engine,"inject_offline","linux-01");
        rejected(engine,"repair","");
        state=engine.action("diagnose","","");check(!list(state,"diagnosis").isEmpty(),"diagnosis exists for occupied and spare nodes");
        state=engine.action("repair","","");
        check(state.get("phase").equals("VERIFYING"),"repair awaits business verification");
        check(list(state,"nodes").stream().allMatch(n->n.get("status").equals("ONLINE")),"all repaired and untouched nodes are ONLINE");
        if(!type.equals("inject_heat")){
            check(((Collection<?>)node(state,id).get("drivers")).contains("SENSOR_DRIVER"),"driver restored");
            check(!((Collection<?>)node(state,id).get("runtimes")).isEmpty(),"runtime restored");
        }
        rejected(engine,"inject_driver",id.isEmpty()?"linux-01":id);
        if(type.equals("inject_heat")){
            state=engine.action("verify","","");check(state.get("phase").equals("VERIFYING"),"heat cannot bypass normal sample requirement");
            for(int i=0;i<7;i++)state=engine.action("step","","");
        }else engine.action("step","","");
        state=engine.action("verify","","");
        check(state.get("phase").equals("RECOVERED")&&(int)state.get("ready")==4,"business verification passes");
        check((boolean)state.get("can_inject"),"next fault enabled");
        check((int)state.get("episode")==number,"episode count continuous");
        check(list(state,"completed_episodes").size()==number,"all prior episodes retained");
        check(list(state,"nodes").stream().allMatch(n->n.get("status").equals("ONLINE")),"no isolated or recovered-only node state");
        int previous=list(state,"completed_episodes").size();state=engine.action("verify","","");
        check(list(state,"completed_episodes").size()==previous,"repeat verification does not duplicate history");
        return state;
    }
    public static void main(String[] args)throws Exception{
        var data=ScenarioLoader.load(Path.of("configs/demo-industrial"));
        for(String algorithm:List.of("first_fit","round_robin","best_fit","beam_search")){
            var engine=new DemoEngine(data,Files.createTempDirectory("iiot-restored-node-").resolve("events.jsonl"));
            engine.action("reset","",algorithm);engine.action("pause","","");int number=0;
            for(var target:data.nodes()){
                for(String type:List.of("inject_offline","inject_driver","inject_runtime")){
                    for(int repeat=1;repeat<=2;repeat++){
                        var state=round(engine,type,target.id(),++number);
                        evidence.add(Map.of("algorithm",algorithm,"node",target.id(),"fault",type,"repeat",repeat,
                            "episode",number,"node_status",node(state,target.id()).get("status"),"ready",state.get("ready")));
                    }
                }
            }
            for(int i=1;i<=2;i++){
                var state=round(engine,"inject_heat","",++number);
                evidence.add(Map.of("algorithm",algorithm,"fault","inject_heat","repeat",i,"episode",number,"ready",state.get("ready")));
            }
            var state=engine.state();check(((List<?>)state.get("completed_faults")).size()==4,"all four fault types completed");
            check((int)state.get("tick")>=number,"clock not reset by repaired nodes");
            state=engine.action("reset","",algorithm);
            check((int)state.get("episode")==0&&list(state,"completed_episodes").isEmpty(),"optional reset still available");
            check(list(state,"nodes").stream().allMatch(n->n.get("status").equals("ONLINE")),"reset ONLINE");
        }
        Files.writeString(Path.of("restored-online-check-results.json"),Json.write(Map.of("status","PASS","assertions",assertions,"rounds",evidence)),StandardCharsets.UTF_8);
        System.out.println("PASS "+assertions+" assertions; "+evidence.size()+" recovery rounds; every node/fault repeated without reset.");
    }
}
