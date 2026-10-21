package org.example.iiot;
import java.nio.file.*;
import java.nio.charset.StandardCharsets;
import java.util.*;
import org.example.iiot.config.ScenarioLoader;
import org.example.iiot.placement.*;
import org.example.iiot.metrics.WorkflowMetrics;

public final class VerificationMain {
    private static int checks=0;
    private static void check(boolean yes,String name){checks++;if(!yes)throw new AssertionError(name);}
    private static Path fixture()throws Exception{
        Path dir=Files.createTempDirectory("iiot-config-check-");
        for(String name:List.of("scenario.properties","nodes.csv","services.csv","variants.csv"))
            Files.copy(Path.of("configs","pressure-c1-uniform",name),dir.resolve(name));
        return dir;
    }
    private static void edit(Path dir,String file,int row,int col,String value)throws Exception{
        var rows=new ArrayList<List<String>>();for(var r:ScenarioLoader.parseCsv(Files.readString(dir.resolve(file),StandardCharsets.UTF_8)))rows.add(new ArrayList<>(r));
        rows.get(row).set(col,value);StringBuilder b=new StringBuilder();
        for(var r:rows){b.append(String.join(",",r.stream().map(s->"\""+s.replace("\"","\"\"")+"\"").toList())).append('\n');}
        Files.writeString(dir.resolve(file),b,StandardCharsets.UTF_8);
    }
    private interface Edit {void run(Path path)throws Exception;}
    private static void invalid(String name,Edit edit)throws Exception{
        Path d=fixture();edit.run(d);boolean rejected=false;
        try{ScenarioLoader.load(d);}catch(IllegalArgumentException|java.io.IOException e){rejected=true;}
        check(rejected,name);
    }
    public static void main(String[] args)throws Exception{
        invalid("unknown schema",p->Files.writeString(p.resolve("scenario.properties"),"schema_version=2\nscenario_id=x\n"));
        invalid("missing schema",p->Files.writeString(p.resolve("scenario.properties"),"scenario_id=x\n"));
        invalid("duplicate property",p->Files.writeString(p.resolve("scenario.properties"),"schema_version=1\nscenario_id=x\nscenario_id=y\n"));
        invalid("unknown property",p->Files.writeString(p.resolve("scenario.properties"),"schema_version=1\nscenario_id=x\nhidden_switch=true\n"));
        invalid("missing architecture",p->edit(p,"nodes.csv",1,6,""));
        invalid("duplicate node",p->edit(p,"nodes.csv",2,0,"linux-01"));
        invalid("unknown OS",p->edit(p,"nodes.csv",1,1,"UNSUPPORTED"));
        invalid("NaN CPU",p->edit(p,"nodes.csv",1,3,"NaN"));
        invalid("zero RAM",p->edit(p,"nodes.csv",1,4,"0"));
        invalid("duplicate set",p->edit(p,"nodes.csv",1,7,"LINUX_CONTAINER|LINUX_CONTAINER"));
        invalid("duplicate service",p->edit(p,"services.csv",2,0,"collect-c1"));
        invalid("unknown dependency",p->edit(p,"services.csv",2,1,"absent"));
        invalid("dependency cycle",p->edit(p,"services.csv",1,1,"alert-c1"));
        invalid("unknown variant service",p->edit(p,"variants.csv",1,1,"absent"));
        invalid("duplicate variant",p->edit(p,"variants.csv",2,0,"collect-linux-c1"));
        invalid("missing runtime",p->edit(p,"variants.csv",1,8,""));
        invalid("negative package",p->edit(p,"variants.csv",1,5,"-1"));
        invalid("unidentified origin",p->edit(p,"variants.csv",1,12,"GUESS"));
        invalid("measured missing evidence",p->{edit(p,"variants.csv",1,12,"MEASURED");edit(p,"variants.csv",1,13,"");});
        invalid("CSV columns",p->Files.writeString(p.resolve("services.csv"),"id,dependencies,unexpected\nx,,1\n"));
        invalid("CSV malformed quote",p->Files.writeString(p.resolve("services.csv"),"id,dependencies\n\"x,broken\n"));
        invalid("missing file",p->Files.delete(p.resolve("nodes.csv")));
        Path quoted=fixture();edit(quoted,"nodes.csv",1,12,"人工声明, 未认证");
        var loaded=ScenarioLoader.load(quoted);check(loaded.origins().get("node:linux-01").contains("人工声明, 未认证"),"Unicode comma field roundtrip");
        boolean immutable=false;try{loaded.nodeCapabilities().clear();}catch(UnsupportedOperationException e){immutable=true;}check(immutable,"immutable loaded maps");
        var data=ScenarioLoader.load(Path.of("configs","objective-conflict"));
        PlatformPolicy.configureExternal("test","full",data.nodeCapabilities(),data.variantRequirements());
        var service=ExactPlanner.solve(data.nodes(),data.services(),"service_first",2000000,10000);
        var workflow=ExactPlanner.solve(data.nodes(),data.services(),"workflow_first",2000000,10000);
        check(service.optimal()&&service.plan().assignments().size()==3&&service.workflows()==0,"service-first counterexample exact");
        check(workflow.optimal()&&workflow.plan().assignments().size()==1&&workflow.workflows()==1,"workflow-first counterexample exact");
        check(!ExactPlanner.solve(data.nodes(),data.services(),"service_first",1,10000).optimal(),"budget exhausted is not optimal");
        var big=ScenarioLoader.load(Path.of("configs","pressure-c3-uniform"));boolean refused=false;
        try{ExactPlanner.solve(big.nodes(),big.services(),"service_first",100,100);}catch(IllegalArgumentException e){refused=true;}check(refused,"large exact case refused");
        var baselines=ScenarioLoader.parseCsv(Files.readString(Path.of("configs","baseline.csv"),StandardCharsets.UTF_8));
        List<Map<String,Object>> results=new ArrayList<>();
        for(String scenario:List.of("pressure-c1-uniform","pressure-c2-uniform","pressure-c1-mixed","objective-conflict")){
            var d=ScenarioLoader.load(Path.of("configs",scenario));
            for(String algorithm:List.of("first_fit","round_robin","best_fit","beam_search","exact_service","exact_workflow")){
                var run=PlanRuntime.run(d,algorithm,64,d.nodes(),d.nodeCapabilities());
                check(run.ready().size()==run.plan().assignments().size(),"CloudSim READY accounting");
                check(Math.abs(run.seconds()-run.predicted())<1e-7,"independent precedence timing vs CloudSim");
                if(scenario.endsWith("uniform")&&!algorithm.startsWith("exact")){
                    var b=baselines.stream().skip(1).filter(r->r.get(0).equals(scenario)&&r.get(1).equals(algorithm)).findFirst().orElseThrow();
                    check(run.ready().size()==Integer.parseInt(b.get(2)),"old formal READY baseline");
                    check(WorkflowMetrics.summarize(d.services(),run.ready()).ready()==Integer.parseInt(b.get(3)),"old formal workflow baseline");
                    check(Math.abs(run.seconds()-Double.parseDouble(b.get(4)))<1e-7,"old formal timing baseline");
                }
                var result=PlanRuntime.describe(d,run);result.put("algorithm",algorithm);results.add(result);
            }
        }
        Path out=Path.of("verification");Files.createDirectories(out);
        Files.writeString(out.resolve("results.json"),Json.write(Map.of("checks",checks,"status","PASS","results",results)),StandardCharsets.UTF_8);
        System.out.println("PASS "+checks+" checks; "+results.size()+" configured planner/CloudSim runs. See verification/results.json");
    }
}
