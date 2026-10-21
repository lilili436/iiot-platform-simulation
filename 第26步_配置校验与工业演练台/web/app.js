const $=id=>document.getElementById(id);
let state=null,busy=false,feedback="";
const stages={collect:"数据采集",preprocess:"数据预处理",detect:"异常检测",alert:"告警发布"};
const phases={RUNNING:"正常运行",FAULT:"故障待诊断",DIAGNOSED:"已定位原因",VERIFYING:"等待恢复验证",DEGRADED:"业务尚未恢复",RECOVERED:"业务已恢复"};
const phaseNotes={RUNNING:"设备采样与服务链可用",FAULT:"平台故障自动触发备用接管；继续诊断故障节点",DIAGNOSED:"修复原节点；已接管的服务保持原位",VERIFYING:"核查服务依赖及工艺数据",DEGRADED:"资源或兼容条件仍不足",RECOVERED:"可继续注入下一项故障，也可选择重置"};
const esc=s=>String(s).replace(/[&<>"']/g,c=>({"&":"&amp;","<":"&lt;",">":"&gt;",'"':"&quot;","'":"&#39;"}[c]));
const fmt=(n,d=1)=>Number(n).toFixed(d);
async function call(path,post=false){
  const response=await fetch(path,{method:post?"POST":"GET",headers:post?{"Content-Type":"application/json"}:{},body:post?"":undefined});
  const data=await response.json();
  if(!response.ok)throw new Error(data.error||"请求失败");
  return data;
}
async function act(name){
  if(busy)return;
  busy=true;renderDisabled();
  try{
    const query=new URLSearchParams({name,node:$("fault-node").value,algorithm:$("algorithm").value});
    state=await call("/api/action?"+query,true);feedback="";render();
  }catch(e){feedback=e.message;$("message").textContent=feedback;$("message").className="message error";}
  finally{busy=false;renderDisabled();}
}
function renderDisabled(){
  if(!state)return;
  const p=state.phase;
  for(const id of ["reset","play","step","algorithm"])$(id).disabled=busy;
  const canInject=state.can_inject;
  $("inject").disabled=busy||!canInject;
  $("fault-type").disabled=busy||!canInject;
  $("fault-node").disabled=busy||!canInject||$("fault-type").value==="inject_heat";
  $("diagnose").disabled=busy||!["FAULT","DIAGNOSED"].includes(p);
  $("repair").disabled=busy||p!=="DIAGNOSED";
  $("verify").disabled=busy||!["VERIFYING","DEGRADED","RECOVERED"].includes(p);
}
function nodePresentation(n){
  return {
    ONLINE:{status:"ONLINE",label:"在线",dot:"good",detail:"节点正常在线；空闲时作为备用，可再次参加故障测试。"},
    OFFLINE:{status:"OFFLINE",label:"离线",dot:"bad",detail:"节点离线，执行修复后恢复在线。"},
    CAPABILITY_GAP:{status:"CAPABILITY_GAP",label:"能力缺口",dot:"warn",detail:"节点能力缺失，执行修复后恢复所需能力。"}
  }[n.status]||{status:n.status,label:n.status,dot:"warn",detail:""};
}

function render(){
  if(!state)return;
  $("connection").textContent="● 本地引擎已连接";$("connection").className="connection";
  $("phase").textContent=phases[state.phase]||state.phase;
  $("phase").className=["FAULT","DEGRADED"].includes(state.phase)?"alert":"";
  $("phase-note").textContent=phaseNotes[state.phase];
  $("ready").textContent=state.ready+" / "+state.requested;
  $("ready").className=state.ready<state.requested?"alert":"";
  $("duration").textContent=fmt(state.deployment_seconds,3)+" s";
  $("clock").textContent=state.tick+" s";
  $("normal").textContent="连续正常采样："+state.normal_samples;
  $("play").textContent=state.playing?"暂停演练":"继续演练";
  if(document.activeElement!==$("algorithm"))$("algorithm").value=state.algorithm;
  const sample=state.samples.at(-1)||{temperature:0,vibration:0,rpm:0,alarm:false};
  $("temperature").textContent=fmt(sample.temperature)+" °C";
  $("temperature").className=sample.alarm?"alert":"";
  $("vibration").textContent=fmt(sample.vibration,2)+" mm/s";
  $("rpm").textContent=fmt(sample.rpm,0)+" rpm";
  $("motor-status").textContent=sample.alarm?"阈值告警":"正常运行";
  $("plant").className="plant"+(sample.alarm?" alarm":"")+(!state.playing?" paused":"");
  $("motor-led").setAttribute("fill",sample.alarm?"#ff737c":"#2dd4bf");
  $("cooling-indicator").textContent=state.cooling_active?"冷却回路：运行中 · 模拟温升衰减":"冷却回路：待命";
  $("cooling-indicator").className="cooling"+(state.cooling_active?" active":"");
  $("workflow-status").textContent=state.ready===state.requested?"完整链可用":"业务链受阻";
  $("chain").innerHTML=state.services.map(s=>'<div class="service '+(s.status==="READY"?"":"blocked")+'"><span class="status">'+(s.status==="READY"?"● 可用":"● 阻断")+'</span><b>'+esc(stages[s.stage]||s.id)+'</b><small>'+esc(s.node)+'</small></div>').join("");
  $("nodes").innerHTML=state.nodes.map(n=>{
    const presentation=nodePresentation(n);
    const status=presentation.label;
    const dot=presentation.dot;
    const cpu=100*n.cpu/n.cpu_total,ram=100*n.ram/n.ram_total;
    const services=state.services.filter(s=>s.node===n.id);
    return '<div class="node '+esc(presentation.status)+'"><div class="node-top"><b>'+esc(n.id)+'</b><span title="'+esc(presentation.detail)+'" class="node-state '+esc(presentation.status)+'"><i class="dot '+dot+'"></i>'+status+'</span></div><div class="os">'+esc(n.os)+'</div><div class="node-cap">'+esc(n.architecture)+' · '+esc(n.runtimes.join(" / ")||"无可用运行环境")+'</div><div class="bar-label"><span>CPU 预留</span><span>'+fmt(n.cpu,0)+' / '+fmt(n.cpu_total,0)+' MIPS</span></div><div class="bar"><i style="width:'+Math.min(100,cpu)+'%"></i></div><div class="bar-label"><span>RAM 预留</span><span>'+n.ram+' / '+n.ram_total+' MiB</span></div><div class="bar ram"><i style="width:'+Math.min(100,ram)+'%"></i></div><div class="node-services">'+(services.length?services.map(s=>'<span class="chip">'+esc(s.stage)+(s.status==="READY"?"":" · 受阻")+'</span>').join(""):'<span class="chip">'+(n.status==="ONLINE"?"备用节点":"待修复")+'</span>')+'</div></div>';
  }).join("");
  if(!state.can_inject&&state.fault)$("fault-type").value=state.fault;
  const selected=$("fault-node").value;
  $("fault-node").innerHTML=state.nodes.map(n=>'<option value="'+esc(n.id)+'"'+(!eligibleNode(n)?' disabled':'')+'>'+esc(n.id)+' · '+esc(n.os)+(n.status==="OFFLINE"?' · 离线':'')+'</option>').join("");
  if(state.nodes.some(n=>n.id===selected&&eligibleNode(n)))$("fault-node").value=selected;
  else recommendNode();
  if(!state.can_inject&&state.fault&&state.nodes.some(n=>n.id===state.fault_node))$("fault-node").value=state.fault_node;
  $("diagnosis-count").textContent=state.diagnosis.length?state.diagnosis.length+" 条":"待检查";
  $("diagnosis").innerHTML=state.diagnosis.length?state.diagnosis.map(d=>'<div class="diagnosis-item"><b>'+esc(d.target)+'</b><code>'+esc(d.reason)+'</code><p>'+esc(d.detail)+'</p></div>').join(""):'<div class="empty">注入故障后执行诊断，将列出直接原因和受影响的依赖。</div>';
  const recoveryNote=state.fault&&state.fault!=="inject_heat"?'<div class="move"><b>'+esc(state.fault_node)+' · '+(["VERIFYING","RECOVERED","DEGRADED"].includes(state.phase)?"已恢复在线备用":"故障节点待修复")+'</b><span>'+(state.standby_shortage?"备用接管不完整，请核查资源和兼容条件。":"服务保留在接管节点，修复后不自动回迁。")+'</span></div>':"";
  $("moves").innerHTML=recoveryNote+(state.moves.length?state.moves.map(m=>'<div class="move"><b>'+esc(m.service)+'</b><span>'+esc(m.from)+' → '+esc(m.to)+'</span></div>').join(""):state.fault==="inject_heat"&&["VERIFYING","RECOVERED"].includes(state.phase)?'<div class="move"><b>开启模拟冷却</b><span>温升按每次采样0.65倍衰减，至少3次连续正常后验证。</span></div>':'<div class="empty">'+(state.phase==="VERIFYING"?"节点已恢复在线备用，保留接管部署；本次无新增迁移。":"平台故障时自动接管；修复后不自动回迁。")+'</div>');
  const phaseNames={TRANSFER:"传输",STARTUP:"启动",READY:"就绪"};
  $("deploy-events").innerHTML=state.deployment_events.map(e=>'<div class="deployment"><b>'+fmt(e.time,3)+' s · '+phaseNames[e.phase]+'</b><span>'+esc(e.service)+'</span><span>'+esc(e.node)+'</span></div>').join("");
  $("history").innerHTML=[...state.history].reverse().map(e=>'<div class="event"><time>'+e.step+' s</time><span>'+esc(e.text)+'</span></div>').join("");
  $("event-count").textContent=state.history.length+" 条";
  $("session").textContent="SESSION "+state.session.slice(0,8);
  if(!feedback){
    $("message").className="message";
    $("message").textContent=state.phase==="RECOVERED"?"本轮恢复验证通过，可以直接选择下一项故障；重置环境可选。累计记录可导出。":state.phase==="VERIFYING"&&state.fault==="inject_heat"?"冷却运行中。推进采样，连续3次正常后点击验证恢复。":phaseNotes[state.phase]+"。";
  }
  const done=state.completed_faults||[];
  $("round-progress").textContent="已完成 "+done.length+" / 4 类故障 · 累计 "+(state.completed_episodes||[]).length+" 轮";
  for(const option of $("fault-type").options){
    option.textContent=faultLabels[option.value]+(done.includes(option.value)?" · 已演示":"");
  }
  drawTrend();renderDisabled();
}
function drawTrend(){
  const w=310,h=130,l=30,t=8,r=8,b=22;
  const low=40,high=100;
  const y=v=>t+(high-v)/(high-low)*(h-t-b);
  const samples=state.samples;
  const x=i=>l+i/Math.max(20,samples.length-1)*(w-l-r);
  const points=samples.map((s,i)=>x(i)+","+y(s.temperature)).join(" ");
  let svg="";
  for(const v of [40,60,80,100])svg+='<line x1="'+l+'" x2="'+(w-r)+'" y1="'+y(v)+'" y2="'+y(v)+'" stroke="#263950"/><text x="3" y="'+(y(v)+3)+'" fill="#839bb7" font-size="9">'+v+'</text>';
  svg+='<line x1="'+l+'" x2="'+(w-r)+'" y1="'+y(80)+'" y2="'+y(80)+'" stroke="#f3b35d" stroke-dasharray="4 4"/><polyline points="'+points+'" fill="none" stroke="#3dd6c6" stroke-width="2"/>';
  svg+='<text x="'+l+'" y="126" fill="#839bb7" font-size="9">最近 '+samples.length+' 次采样 / 演练秒</text>';
  $("trend").innerHTML=svg;
}
const faultLabels={inject_offline:"平台故障 · 节点离线",inject_driver:"适配故障 · 传感器驱动缺失",inject_runtime:"适配故障 · 运行环境不可用",inject_heat:"工艺故障 · 电机温度过高"};
function eligibleNode(n){
  if(n.status==="OFFLINE")return false;
  const type=$("fault-type").value;
  if(type==="inject_driver")return n.drivers.includes("SENSOR_DRIVER");
  if(type==="inject_runtime")return n.runtimes.length>0;
  return true;
}
function recommendNode(){
  if(!state)return;
  const type=$("fault-type").value;
  const stage=type==="inject_runtime"?"detect":"collect";
  const current=state.services.find(s=>s.stage===stage)?.node;
  const candidate=state.nodes.find(n=>n.id===current&&eligibleNode(n))||state.nodes.find(eligibleNode);
  $("fault-node").value=candidate?.id||"";
}
function chooseFault(){
  const heat=$("fault-type").value==="inject_heat";
  $("fault-hint").textContent=heat?"工艺异常：平台部署不变，检查温度阈值并开启模拟冷却。":"建议选择承载服务的节点：故障后自动由兼容备用接管，修复后原节点在线备用，不自动回迁。";
  if(state&&state.can_inject&&!heat){
    recommendNode();
  }
  if(state){
    for(const option of $("fault-node").options){
      const node=state.nodes.find(n=>n.id===option.value);option.disabled=!node||!eligibleNode(node);
    }
  }
  renderDisabled();
}
$("reset").onclick=()=>{feedback="";act("reset");};
$("algorithm").onchange=()=>act("reset");
$("play").onclick=()=>act(state?.playing?"pause":"play");
$("step").onclick=()=>act("step");
$("inject").onclick=()=>act($("fault-type").value);
$("diagnose").onclick=()=>act("diagnose");
$("repair").onclick=()=>act("repair");
$("verify").onclick=()=>act("verify");
$("fault-type").onchange=chooseFault;
(async()=>{try{state=await call("/api/state");render();chooseFault();}catch(e){$("connection").textContent="连接失败";$("connection").className="connection error";$("message").textContent=e.message;}})();
setInterval(async()=>{if(busy)return;busy=true;try{state=await call("/api/tick",true);render();}catch(e){$("connection").textContent="连接断开 · 请检查终端";$("connection").className="connection error";}finally{busy=false;renderDisabled();}},1000);
