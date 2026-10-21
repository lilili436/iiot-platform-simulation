import argparse,json,subprocess,time,urllib.request,urllib.error,socket
from pathlib import Path
def main():
 p=argparse.ArgumentParser();p.add_argument("--java",required=True);p.add_argument("--classpath",required=True);p.add_argument("--project",required=True);p.add_argument("--toolkit",required=True);p.add_argument("--node",required=True);p.add_argument("--out",required=True);a=p.parse_args()
 root=Path(a.out);root.mkdir(parents=True,exist_ok=True);checks=0
 with socket.socket() as s:s.bind(("127.0.0.1",0));port=s.getsockname()[1]
 base="http://127.0.0.1:"+str(port)
 def get(path):return json.load(urllib.request.urlopen(base+path,timeout=5))
 def action(name,node="",platform=""):
  req=urllib.request.Request(base+"/api/action?name="+name+"&node="+node+"&platform="+platform,data=b"",headers={"Content-Type":"application/json"},method="POST")
  return json.load(urllib.request.urlopen(req,timeout=10))
 with (root/"ui-api-server.log").open("w",encoding="utf-8") as log:
  child=subprocess.Popen([a.java,"-Dfile.encoding=UTF-8","-cp",a.classpath,"org.example.iiot.demo.DemoServer",str(port)],cwd=a.project,stdout=log,stderr=subprocess.STDOUT)
  try:
   deadline=time.monotonic()+25
   while True:
    try:state=get("/api/state");break
    except OSError:
     if child.poll() is not None or time.monotonic()>deadline:raise RuntimeError("Java test server failed; inspect ui-api-server.log")
     time.sleep(.1)
   assert state["ready"]==4;checks+=1
   initial=state
   action("settings",platform="WINDOWS")
   failed=action("inject_driver","vx-01")
   assert failed["ready"]==4;checks+=1
   moved=[x for x in failed["services"] if x["stage"]!="detect"]
   assert all(x["node"].startswith("win-") and "-win-" in x["variant"] for x in moved);checks+=1
   assert next(x for x in failed["nodes"] if x["id"]=="vx-01")["status"]=="CAPABILITY_GAP";checks+=1
   action("diagnose");repaired=action("repair");verified=action("verify")
   assert verified["phase"]=="RECOVERED";checks+=1
   vx=next(x for x in verified["nodes"] if x["id"]=="vx-01")
   assert vx["status"]=="ONLINE" and vx["role"]=="STANDBY" and vx["cpu"]==vx["ram"]==0;checks+=1
   assert failed["services"]==repaired["services"]==verified["services"];checks+=1
   assert all(x["from_os"]=="VXWORKS" and x["to_os"]=="WINDOWS" for x in verified["moves"]);checks+=1
   exported=get("/api/export")
   assert len(exported["completed_episodes"])==1 and exported["completed_episodes"][0]["takeover_platform"]=="WINDOWS";checks+=1
   fixture=root/"windows-recovered.json";fixture.write_text(json.dumps(verified,ensure_ascii=False,indent=2),encoding="utf-8")
   (root/"windows-takeover-trace.json").write_text(json.dumps(dict(initial=initial,fault=failed,repaired=repaired,verified=verified,export=exported),ensure_ascii=False,indent=2),encoding="utf-8")
   action("settings",platform="VXWORKS")
   before=get("/api/state");detect=next(x for x in before["services"] if x["stage"]=="detect")["node"]
   try:action("inject_runtime",detect);raise AssertionError("incompatible forced takeover accepted")
   except urllib.error.HTTPError as ex:assert ex.code==400;checks+=1
   assert get("/api/state")==before;checks+=1
   html=urllib.request.urlopen(base+"/").read().decode()
   assert 'id="takeover-platform"' in html and "Windows 接管" in html;checks+=1
   subprocess.run([a.node,"--check",str(Path(a.toolkit)/"web/app.js")],check=True)
   subprocess.run([a.node,str(Path(a.toolkit)/"验证证据/check-platform-render.cjs"),str(Path(a.toolkit)/"web/app.js"),str(fixture),str(root/"ui-render-checks.json")],check=True)
   checks+=json.loads((root/"ui-render-checks.json").read_text())["checks"]
   (root/"ui-api-checks.json").write_text(json.dumps(dict(status="PASS",checks=checks,scope="HTTP Windows takeover, version switch, no failback, export, atomic incompatible rejection, renderer"),ensure_ascii=False,indent=2),encoding="utf-8")
   print("PASS "+str(checks)+" HTTP/UI checks")
  finally:
   child.terminate()
   try:child.wait(timeout=5)
   except subprocess.TimeoutExpired:child.kill();child.wait()
if __name__=="__main__":main()
