package org.example.iiot;
import java.nio.file.*;
import java.nio.charset.StandardCharsets;
import org.example.iiot.config.ScenarioLoader;
public final class ScenarioMain {
    public static void main(String[] args)throws Exception{
        if(args.length<3||args.length>4)throw new IllegalArgumentException("Usage: <configDir> <algorithm> <outputJson> [beamWidth]");
        var data=ScenarioLoader.load(Path.of(args[0]));
        int width=args.length==4?Integer.parseInt(args[3]):64;
        if(width<=0)throw new IllegalArgumentException("beamWidth must be positive");
        var run=PlanRuntime.run(data,args[1],width,data.nodes(),data.nodeCapabilities());
        var summary=PlanRuntime.describe(data,run);summary.put("algorithm",args[1]);
        Path output=Path.of(args[2]);Files.createDirectories(output.toAbsolutePath().getParent());
        Files.writeString(output,Json.write(summary),StandardCharsets.UTF_8);
        System.out.println("CONFIG_RESULT: "+output.toAbsolutePath());
        System.out.println("Exact completion certified: "+(run.exact()&&run.optimal()));
    }
}
