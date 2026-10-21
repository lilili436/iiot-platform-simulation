package org.example.iiot;
import java.util.*;
public final class Json {
    private Json(){}
    public static String write(Object value){
        if(value==null)return "null";
        if(value instanceof String s){
            StringBuilder b=new StringBuilder("\"");
            for(char c:s.toCharArray())switch(c){
                case '"' -> b.append("\\\"");case '\\' -> b.append("\\\\");
                case '\n' -> b.append("\\n");case '\r' -> b.append("\\r");case '\t' -> b.append("\\t");
                default -> {if(c<32)b.append(String.format("\\u%04x",(int)c));else b.append(c);}
            }return b.append('"').toString();
        }
        if(value instanceof Boolean)return value.toString();
        if(value instanceof Number n){if(!Double.isFinite(n.doubleValue()))throw new IllegalArgumentException("Non-finite JSON number");return n.toString();}
        if(value instanceof Map<?,?> m){
            List<String> parts=new ArrayList<>();for(var e:m.entrySet())parts.add(write(e.getKey().toString())+":"+write(e.getValue()));
            return "{"+String.join(",",parts)+"}";
        }
        if(value instanceof Collection<?> c)return "["+String.join(",",c.stream().map(Json::write).toList())+"]";
        throw new IllegalArgumentException("Unsupported JSON type "+value.getClass());
    }
}
