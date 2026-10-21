package org.example.iiot.demo;
import com.sun.net.httpserver.*;
import java.nio.file.*;
import java.nio.charset.StandardCharsets;
import java.net.*;
import java.io.*;
import java.util.*;
import java.util.concurrent.Executors;
import org.example.iiot.Json;
import org.example.iiot.config.ScenarioLoader;

public final class DemoServer {
    public static void main(String[] args)throws Exception{
        int port=args.length==0?8765:Integer.parseInt(args[0]);
        if(port<1024||port>65535)throw new IllegalArgumentException("Port must be 1024..65535");
        var data=ScenarioLoader.load(Path.of("configs","demo-industrial"));
        DemoEngine engine=new DemoEngine(data,Path.of("demo-session","events.jsonl"));
        HttpServer server=HttpServer.create(new InetSocketAddress("127.0.0.1",port),0);
        server.createContext("/",exchange->{
            try{
                String path=exchange.getRequestURI().getPath(),method=exchange.getRequestMethod();
                String origin=exchange.getRequestHeaders().getFirst("Origin");
                if(origin!=null&&!origin.equals("http://127.0.0.1:"+port)&&!origin.equals("http://localhost:"+port)){
                    send(exchange,403,"application/json",Json.write(Map.of("error","Origin rejected")));return;
                }
                if(path.equals("/api/state")&&method.equals("GET"))send(exchange,200,"application/json",Json.write(engine.state()));
                else if(path.equals("/api/export")&&method.equals("GET")){
                    exchange.getResponseHeaders().set("Content-Disposition","attachment; filename=industrial-demo-session.json");
                    send(exchange,200,"application/json",Json.write(engine.export()));
                }else if((path.equals("/api/action")||path.equals("/api/tick"))&&method.equals("POST")){
                    String ct=exchange.getRequestHeaders().getFirst("Content-Type");
                    if(ct==null||!ct.startsWith("application/json")){send(exchange,415,"application/json",Json.write(Map.of("error","application/json required")));return;}
                    Map<String,String> query=new HashMap<>();
                    String q=exchange.getRequestURI().getRawQuery();
                    if(q!=null)for(String item:q.split("&")){String[] p=item.split("=",2);query.put(URLDecoder.decode(p[0],StandardCharsets.UTF_8),p.length==2?URLDecoder.decode(p[1],StandardCharsets.UTF_8):"");}
                    var result=path.equals("/api/tick")?engine.advance():engine.action(query.getOrDefault("name",""),query.getOrDefault("node",""),query.getOrDefault("algorithm",""));
                    send(exchange,200,"application/json",Json.write(result));
                }else if(method.equals("GET")&&Set.of("/","/app.js","/style.css").contains(path)){
                    String name=path.equals("/")?"index.html":path.substring(1);
                    send(exchange,200,path.endsWith(".js")?"text/javascript":path.endsWith(".css")?"text/css":"text/html",Files.readString(Path.of("web",name),StandardCharsets.UTF_8));
                }else send(exchange,404,"application/json",Json.write(Map.of("error","Not found")));
            }catch(IllegalArgumentException e){send(exchange,400,"application/json",Json.write(Map.of("error",e.getMessage())));}
            catch(Exception e){e.printStackTrace();send(exchange,500,"application/json",Json.write(Map.of("error","本地演示执行失败，请检查终端日志。")));}
            finally{exchange.close();}
        });
        server.setExecutor(Executors.newFixedThreadPool(4));server.start();
        System.out.println("INDUSTRIAL DEMO: http://127.0.0.1:"+port);
        System.out.println("Synthetic environment. Keep this terminal open; Ctrl+C stops the server.");
    }
    private static void send(HttpExchange e,int code,String type,String body)throws IOException{
        byte[] bytes=body.getBytes(StandardCharsets.UTF_8);
        e.getResponseHeaders().set("Content-Type",type+"; charset=utf-8");
        e.getResponseHeaders().set("Cache-Control","no-store");
        e.getResponseHeaders().set("X-Content-Type-Options","nosniff");
        e.sendResponseHeaders(code,bytes.length);e.getResponseBody().write(bytes);
    }
}
