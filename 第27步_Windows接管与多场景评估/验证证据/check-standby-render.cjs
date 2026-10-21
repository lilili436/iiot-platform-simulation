
const fs=require("fs"),vm=require("vm"),assert=require("assert");
let source=fs.readFileSync(process.argv[2],"utf8");
source=source.slice(0,source.indexOf('$("reset").onclick'));
const fixture=JSON.parse(fs.readFileSync(process.argv[3],"utf8"));
const elements=new Map();
function element(id){if(!elements.has(id))elements.set(id,{
 value:id==="fault-type"?"inject_driver":id==="fault-node"?"vx-01":"",
 options:id==="fault-type"?["inject_offline","inject_driver","inject_runtime","inject_heat"].map(value=>({value,textContent:""})):[],
 innerHTML:"",textContent:"",className:"",disabled:false,setAttribute(){}
});return elements.get(id)}
const context={document:{getElementById:element},fixture,fetch(){throw Error("Unexpected network")},URLSearchParams,setInterval(){}};
vm.createContext(context);vm.runInContext(source+'\nstate=fixture;render();',context);
assert(element("nodes").innerHTML.includes('备用节点'));
const vx=element("nodes").innerHTML.split('<b>vx-01</b>')[1].split('<b>vx-02</b>')[0];
assert(vx.includes('class="node-state ONLINE"'));
assert(vx.includes('0 / 2000 MIPS'));
assert(vx.includes('0 / 1024 MiB'));
assert(vx.includes('备用节点')&&!vx.includes('受阻'));
assert(element("moves").innerHTML.includes('vx-01 · 已恢复在线备用'));
assert(element("moves").innerHTML.includes('vx-01 → vx-02'));
assert.equal((element("chain").innerHTML.match(/vx-02/g)||[]).length,3);
assert.equal(element("inject").disabled,false);
const active={...fixture,phase:"FAULT",can_inject:false,fault:"inject_runtime"};
context.active=active;vm.runInContext('state=active;render();',context);
assert.equal(element("fault-type").value,"inject_runtime");
fs.writeFileSync(process.argv[4],JSON.stringify({status:"PASS",checks:10,scope:"render repaired standby, takeover locations, actions, and active fault selection"}));
console.log("PASS 10 full-render state checks");
