const fs=require("fs"),vm=require("vm"),assert=require("assert");
const source=fs.readFileSync(process.argv[2],"utf8");
const context={$:()=>({value:context.type}),type:"inject_offline"};vm.createContext(context);
for(const name of ["nodePresentation","eligibleNode"]){
 const start=source.indexOf("function "+name+"("),end=source.indexOf("\n}",start)+2;
 vm.runInContext(source.slice(start,end),context);
}
let checks=0;
const nodes=["linux-01","linux-02","win-01","win-02","vx-01","vx-02"];
for(const id of nodes)for(const type of ["inject_offline","inject_driver","inject_runtime"]){
 context.type=type;const node={id,status:"ONLINE",drivers:["SENSOR_DRIVER"],runtimes:["RUNTIME"]};
 assert(context.eligibleNode(node));checks++;
 const displayed=context.nodePresentation(node);
 assert.equal(displayed.label,"在线");assert.equal(displayed.status,"ONLINE");checks+=2;
 // Repaired targets have the same actual capabilities, independent of their history.
 assert(context.eligibleNode({...node,was_repaired:true}));checks++;
}
context.type="inject_driver";assert(!context.eligibleNode({status:"CAPABILITY_GAP",drivers:[],runtimes:["R"]}));checks++;
context.type="inject_runtime";assert(!context.eligibleNode({status:"CAPABILITY_GAP",drivers:["SENSOR_DRIVER"],runtimes:[]}));checks++;
assert(!source.includes("ISOLATED_RECOVERED")&&!source.includes("ADAPTED_RECOVERED")&&!source.includes("AWAITING_VERIFICATION"));checks++;
fs.writeFileSync(process.argv[3],JSON.stringify({status:"PASS",assertions:checks,scope:"all six restored ONLINE nodes selectable; only ONLINE/OFFLINE/CAPABILITY_GAP labels"},null,2));
console.log("PASS "+checks+" UI eligibility/label assertions");
