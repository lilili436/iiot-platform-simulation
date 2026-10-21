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
const vx=element("nodes").innerHTML.split('<b>vx-01</b>')[1].split('<b>vx-02</b>')[0];
assert(vx.includes('class="node-state ONLINE"'));assert(vx.includes('0 / 2000 MIPS'));assert(vx.includes('备用节点'));
assert(element("moves").innerHTML.includes('VXWORKS → WINDOWS'));
assert(element("moves").innerHTML.includes('collect-vx-c1 → collect-win-c1'));
assert(element("chain").innerHTML.includes('collect-win-c1'));
assert(element("chain").innerHTML.includes('detect-linux-c1'));
assert.equal(element("takeover-platform").value,"WINDOWS");
assert.equal(element("takeover-platform").disabled,false);
assert.equal(element("inject").disabled,false);
context.active={...fixture,phase:"FAULT",can_inject:false,fault:"inject_runtime"};
vm.runInContext('state=active;render();',context);
assert.equal(element("fault-type").value,"inject_runtime");assert.equal(element("takeover-platform").disabled,true);
fs.writeFileSync(process.argv[4],JSON.stringify({status:"PASS",checks:12,scope:"Windows variants and takeover platform displayed, repaired node standby, action states"}));
console.log("PASS 12 Windows render checks");
