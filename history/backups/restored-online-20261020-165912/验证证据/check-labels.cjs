const fs=require("fs"),vm=require("vm"),assert=require("assert");
const source=fs.readFileSync(process.argv[2],"utf8");
const begin=source.indexOf("function nodePresentation(n){"),end=source.indexOf("\nfunction render(){",begin);
const context={state:{}};vm.createContext(context);vm.runInContext(source.slice(begin,end),context);
let checks=0;const results=[];
function test(name,state,status,expected){
  context.state=state;const node={id:"vx-01",status};const before=JSON.stringify(node);
  const result=context.nodePresentation(node);
  assert.equal(result.status,expected,name);assert.equal(JSON.stringify(node),before,"must preserve underlying node state");
  checks+=2;results.push({name,technical_status:status,display_status:result.status,label:result.label});
}
const base={fault_node:"vx-01",can_inject:false,ready:0,requested:4,completed_episodes:[]};
test("driver fault before repair",{...base,phase:"FAULT"},"CAPABILITY_GAP","CAPABILITY_GAP");
test("offline fault before repair",{...base,phase:"FAULT"},"OFFLINE","OFFLINE");
test("repair completed before verification",{...base,phase:"VERIFYING",ready:4},"CAPABILITY_GAP","AWAITING_VERIFICATION");
test("offline migrated before verification",{...base,phase:"VERIFYING",ready:4},"OFFLINE","AWAITING_VERIFICATION");
const completed={...base,phase:"RECOVERED",can_inject:true,ready:4,completed_episodes:[{node:"vx-01",fault:"inject_driver"}]};
test("driver resolved",completed,"CAPABILITY_GAP","ADAPTED_RECOVERED");
test("offline resolved",completed,"OFFLINE","ISOLATED_RECOVERED");
test("next unrelated round preserves handled node",{...completed,phase:"FAULT",can_inject:false,fault_node:"linux-01"},"CAPABILITY_GAP","ADAPTED_RECOVERED");
test("reinject same node shows fresh fault",{...completed,phase:"FAULT",can_inject:false},"CAPABILITY_GAP","CAPABILITY_GAP");
test("failed repair is not falsely marked recovered",{...completed,phase:"DEGRADED",can_inject:false,ready:2},"CAPABILITY_GAP","CAPABILITY_GAP");
test("incomplete availability before verification",{...base,phase:"VERIFYING",ready:2},"OFFLINE","OFFLINE");
test("reset restores normal presentation",{...base,phase:"RUNNING",can_inject:true},"ONLINE","ONLINE");
test("unresolved capability remains gap",{...base,phase:"RUNNING",can_inject:true},"CAPABILITY_GAP","CAPABILITY_GAP");
test("earlier resolved node remains handled during heat",{...completed,phase:"VERIFYING",can_inject:false,fault_node:"motor-01"},"OFFLINE","ISOLATED_RECOVERED");
fs.writeFileSync(process.argv[3],JSON.stringify({status:"PASS",assertions:checks,cases:results},null,2));
console.log("PASS "+checks+" assertions across "+results.length+" node lifecycle cases");
