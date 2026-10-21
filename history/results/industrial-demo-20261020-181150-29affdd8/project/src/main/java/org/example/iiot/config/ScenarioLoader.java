package org.example.iiot.config;
import java.nio.file.*;
import java.nio.charset.StandardCharsets;
import java.util.*;
import java.io.*;
import org.example.iiot.model.*;
import org.example.iiot.placement.PlatformPolicy.*;

public final class ScenarioLoader {
    private ScenarioLoader(){}
    public record Data(String id,List<NodeSpec> nodes,List<ServiceSpec> services,
        Map<String,Capabilities> nodeCapabilities,Map<String,Requirements> variantRequirements,
        Map<String,String> origins,Path source) {
        public Data { nodes=List.copyOf(nodes);services=List.copyOf(services);
            nodeCapabilities=Map.copyOf(nodeCapabilities);variantRequirements=Map.copyOf(variantRequirements);
            origins=Map.copyOf(origins); }
    }
    public static Data load(Path directory) throws IOException {
        Path root=directory.toAbsolutePath().normalize();
        Map<String,String> props=new LinkedHashMap<>();
        int line=0;
        for(String raw:Files.readAllLines(root.resolve("scenario.properties"),StandardCharsets.UTF_8)){
            line++;String s=raw.replace("\uFEFF","").trim();
            if(s.isEmpty()||s.startsWith("#"))continue;
            int eq=s.indexOf('=');
            if(eq<1)throw fail("scenario.properties",line,"Expected key=value");
            String key=s.substring(0,eq).trim(),value=s.substring(eq+1).trim();
            if(!Set.of("schema_version","scenario_id","description").contains(key))throw fail("scenario.properties",line,"Unknown key "+key);
            if(props.putIfAbsent(key,value)!=null)throw fail("scenario.properties",line,"Duplicate key "+key);
        }
        if(!"1".equals(props.get("schema_version")))throw new IllegalArgumentException("schema_version must be 1");
        String id=identifier(props.get("scenario_id"));
        List<NodeSpec> nodes=new ArrayList<>();Map<String,Capabilities> caps=new LinkedHashMap<>();
        Map<String,String> origins=new LinkedHashMap<>();
        for(var r:table(root,"nodes.csv","id,os,cores,mips_per_core,memory_mib,bandwidth_mibps,architecture,runtimes,apis,drivers,security,origin,evidence")){
            String nid=identifier(required(r,"id"));OsType os=OsType.valueOf(required(r,"os"));
            NodeSpec n=new NodeSpec(nid,os,integer(r,"cores"),number(r,"mips_per_core"),integer(r,"memory_mib"),number(r,"bandwidth_mibps"));
            if(!Double.isFinite(n.totalMips()))throw new IllegalArgumentException("CPU capacity overflow: "+nid);
            if(caps.putIfAbsent(nid,new Capabilities(token(required(r,"architecture")),tokens(r.get("runtimes")),tokens(r.get("apis")),tokens(r.get("drivers")),tokens(r.get("security"))))!=null)
                throw new IllegalArgumentException("Duplicate node id: "+nid);
            nodes.add(n);origins.put("node:"+nid,origin(r));
        }
        Map<String,List<String>> deps=new LinkedHashMap<>();Map<String,List<ServiceVariant>> variants=new LinkedHashMap<>();
        for(var r:table(root,"services.csv","id,dependencies")){
            String sid=identifier(required(r,"id"));List<String> d=new ArrayList<>(tokens(r.get("dependencies")));
            for(String dep:d)identifier(dep);
            if(deps.putIfAbsent(sid,List.copyOf(d))!=null)throw new IllegalArgumentException("Duplicate service id: "+sid);
            variants.put(sid,new ArrayList<>());
        }
        Map<String,Requirements> reqs=new LinkedHashMap<>();
        for(var r:table(root,"variants.csv","id,service_id,os,cpu_mips,memory_mib,package_mib,startup_seconds,architecture,runtime,apis,drivers,security,origin,evidence")){
            String vid=identifier(required(r,"id")),sid=required(r,"service_id");
            if(!variants.containsKey(sid))throw new IllegalArgumentException("Variant references unknown service: "+sid);
            ServiceVariant v=new ServiceVariant(vid,OsType.valueOf(required(r,"os")),number(r,"cpu_mips"),integer(r,"memory_mib"),number(r,"package_mib"),number(r,"startup_seconds"));
            if(reqs.putIfAbsent(vid,new Requirements(token(required(r,"architecture")),token(required(r,"runtime")),tokens(r.get("apis")),tokens(r.get("drivers")),tokens(r.get("security"))))!=null)
                throw new IllegalArgumentException("Duplicate variant id: "+vid);
            variants.get(sid).add(v);origins.put("variant:"+vid,origin(r));
        }
        if(nodes.isEmpty()||deps.isEmpty())throw new IllegalArgumentException("Nodes and services must not be empty");
        for(var e:deps.entrySet()){
            if(variants.get(e.getKey()).isEmpty())throw new IllegalArgumentException("No variants: "+e.getKey());
            for(String d:e.getValue())if(!deps.containsKey(d))throw new IllegalArgumentException("Unknown dependency: "+d);
        }
        List<ServiceSpec> ordered=new ArrayList<>();Set<String> done=new HashSet<>();
        while(done.size()<deps.size()){
            boolean changed=false;
            for(String sid:deps.keySet())if(!done.contains(sid)&&done.containsAll(deps.get(sid))){
                ordered.add(new ServiceSpec(sid,deps.get(sid),variants.get(sid)));done.add(sid);changed=true;
            }
            if(!changed)throw new IllegalArgumentException("Dependency cycle in services.csv");
        }
        return new Data(id,nodes,ordered,caps,reqs,origins,root);
    }
    private static String origin(Map<String,String> row){
        String kind=required(row,"origin"),evidence=required(row,"evidence");
        if(!Set.of("SYNTHETIC","MEASURED").contains(kind))throw new IllegalArgumentException("origin must be SYNTHETIC or MEASURED");
        return kind+":"+evidence; // A declared evidence reference is not an automatic certification.
    }
    private static String required(Map<String,String> r,String key){
        String v=r.get(key);if(v==null||v.isBlank())throw new IllegalArgumentException("Missing required field "+key);return v;
    }
    private static double number(Map<String,String> r,String k){
        double v=Double.parseDouble(required(r,k));if(!Double.isFinite(v))throw new IllegalArgumentException("Non-finite "+k);return v;
    }
    private static int integer(Map<String,String> r,String k){return Integer.parseInt(required(r,k));}
    private static String identifier(String s){
        if(s==null||!s.matches("[A-Za-z0-9][A-Za-z0-9_.-]{0,79}"))throw new IllegalArgumentException("Invalid id: "+s);return s;
    }
    private static String token(String s){
        if(!s.matches("[A-Z0-9_]+"))throw new IllegalArgumentException("Invalid capability token: "+s);return s;
    }
    private static Set<String> tokens(String s){
        Set<String> set=new LinkedHashSet<>();if(s==null||s.isEmpty())return set;
        for(String part:s.split("\\|",-1)){
            String t=part.trim();
            // Dependencies also use this separator and may contain lowercase/dashes.
            if(t.isEmpty()||!set.add(t))throw new IllegalArgumentException("Empty or duplicate set member: "+s);
        }return set;
    }
    private static IllegalArgumentException fail(String file,int row,String reason){
        return new IllegalArgumentException(file+":"+row+": "+reason);
    }
    private static List<Map<String,String>> table(Path root,String file,String header) throws IOException {
        List<List<String>> rows=parseCsv(Files.readString(root.resolve(file),StandardCharsets.UTF_8));
        if(rows.isEmpty()||!rows.get(0).equals(Arrays.asList(header.split(","))))throw fail(file,1,"Header/schema mismatch");
        List<Map<String,String>> out=new ArrayList<>();List<String> names=rows.get(0);
        for(int i=1;i<rows.size();i++){
            List<String> fields=rows.get(i);if(fields.size()==1&&fields.get(0).isBlank())continue;
            if(fields.size()!=names.size())throw fail(file,i+1,"Expected "+names.size()+" columns; got "+fields.size());
            Map<String,String> r=new LinkedHashMap<>();
            for(int j=0;j<names.size();j++)r.put(names.get(j),fields.get(j).trim());
            out.add(r);
        }return out;
    }
    public static List<List<String>> parseCsv(String text){
        if(text.startsWith("\uFEFF"))text=text.substring(1);
        List<List<String>> rows=new ArrayList<>();List<String> row=new ArrayList<>();StringBuilder field=new StringBuilder();
        boolean quoted=false,closed=false;
        for(int i=0;i<text.length();i++){
            char c=text.charAt(i);
            if(quoted){
                if(c=='"'){if(i+1<text.length()&&text.charAt(i+1)=='"'){field.append('"');i++;}else{quoted=false;closed=true;}}
                else field.append(c);
            }else if(c=='"'){if(field.length()!=0||closed)throw new IllegalArgumentException("Unexpected CSV quote");quoted=true;}
            else if(c==','||c=='\n'||c=='\r'){
                row.add(field.toString());field.setLength(0);closed=false;
                if(c!=','){rows.add(List.copyOf(row));row.clear();if(c=='\r'&&i+1<text.length()&&text.charAt(i+1)=='\n')i++;}
            }else{if(closed)throw new IllegalArgumentException("Text after closing CSV quote");field.append(c);}
        }
        if(quoted)throw new IllegalArgumentException("Unclosed CSV quote");
        if(field.length()>0||!row.isEmpty()||closed){row.add(field.toString());rows.add(List.copyOf(row));}
        return List.copyOf(rows);
    }
}
