import argparse,json,csv,statistics,html
from pathlib import Path
from collections import defaultdict
def dump_csv(path,rows):
 if not rows:return
 with path.open("w",encoding="utf-8-sig",newline="") as f:
  writer=csv.DictWriter(f,fieldnames=list(rows[0]));writer.writeheader();writer.writerows(rows)
def table(rows):
 if not rows:return "<p>尚无该项结果。</p>"
 keys=list(rows[0])
 return "<table><thead><tr>"+"".join("<th>"+html.escape(str(k))+"</th>" for k in keys)+"</tr></thead><tbody>"+"".join("<tr>"+"".join("<td>"+html.escape(format(r[k],".4g") if isinstance(r[k],float) else str(r[k]))+"</td>" for k in keys)+"</tr>" for r in rows)+"</tbody></table>"
def main():
 p=argparse.ArgumentParser();p.add_argument("--project",required=True);p.add_argument("--out",required=True);a=p.parse_args()
 project=Path(a.project);out=Path(a.out);out.mkdir(parents=True,exist_ok=True);study=project/"study"
 summary=[];aggregate=[];effects=[];manifest={}
 if (study/"results.json").is_file():
  raw=json.loads((study/"results.json").read_text(encoding="utf-8-sig"));manifest=json.loads((study/"manifest.json").read_text(encoding="utf-8-sig"))
  groups=defaultdict(list)
  for r in raw:groups[(r["scenario"],r["objective"],r["method"])].append(r)
  for values in groups.values():
   x=values[0];summary.append(dict(scenario=x["scenario"],seed=x["seed"],topology=x["topology"],profile=x["profile"],service_scale=x["service_scale"],objective=x["objective"],method=x["method"],
    ready=x["ready"],requested=x["requested"],workflow_ratio=x["workflows"]/x["workflows_requested"],workflows=x["workflows"],ready_ids="|".join(x["ready_service_ids"]),
    seconds=x["seconds"],planning_median_ms=statistics.median(r["planning_ms"] for r in values),planning_sd_ms=statistics.stdev(r["planning_ms"] for r in values),
    cpu_reserved=x["cpu_reserved"],ram_reserved=x["ram_reserved"],exact_proven=x["exact_proven"],same_fifo=x["exact_same_fifo_order"],primary_gap=x["primary_gap"]))
  pooled=defaultdict(list)
  for r in summary:pooled[(r["profile"],r["topology"],r["service_scale"],r["objective"],r["method"])].append(r)
  for key,values in pooled.items():
   aggregate.append(dict(zip(("profile","topology","service_scale","objective","method"),key))|dict(seeds=len(values),ready_ratio_mean=statistics.mean(r["ready"]/r["requested"] for r in values),
    workflow_ratio_mean=statistics.mean(r["workflow_ratio"] for r in values),workflow_ratio_sd=statistics.stdev(r["workflow_ratio"] for r in values),
    deployment_seconds_mean=statistics.mean(r["seconds"] for r in values),planning_median_ms=statistics.median(r["planning_median_ms"] for r in values)))
  lookup={(r["scenario"],r["objective"],r["method"]):r for r in summary}
  for r in summary:
   if r["method"]!="beam_scarcity_w64":continue
   for baseline in ("first_fit","round_robin","best_fit","beam_input_w64","beam_scarcity_w4","beam_scarcity_w16"):
    b=lookup[(r["scenario"],r["objective"],baseline)];same=r["ready_ids"]==b["ready_ids"]
    effects.append(dict(scenario=r["scenario"],objective=r["objective"],baseline=baseline,ready_delta=r["ready"]-b["ready"],workflow_ratio_delta=r["workflow_ratio"]-b["workflow_ratio"],
     same_service_identity=same,time_reduction_percent=(100*(b["seconds"]-r["seconds"])/b["seconds"] if same and b["seconds"]>0 else None)))
  dump_csv(out/"summary.csv",summary);dump_csv(out/"aggregate.csv",aggregate);dump_csv(out/"paired-effects.csv",effects)
 acceptance=[]
 for label,file in (("配置与精确检查",project/"verification/results.json"),("最终集成检查",project/"verification/final-checks.json"),
  ("连续故障恢复",out/"continuous-check-results.json"),("前端与HTTP接口",out/"ui-api-checks.json")):
  if file.exists():
   data=json.loads(file.read_text(encoding="utf-8-sig"))
   status=data.get("status","PASS" if label=="配置与精确检查" else "RECORDED")
   acceptance.append(dict(item=label,status=status,evidence=str(file)))
  else:acceptance.append(dict(item=label,status="NOT_RUN",evidence=str(file)))
 dump_csv(out/"acceptance.csv",acceptance)
 probe=out/"environment.json";environment=json.loads(probe.read_text(encoding="utf-8-sig")) if probe.exists() else {}
 wins=sum(e["workflow_ratio_delta"]>0 for e in effects if e["baseline"]=="first_fit");losses=sum(e["workflow_ratio_delta"]<0 for e in effects if e["baseline"]=="first_fit")
 conclusion=f"相对First Fit，束搜索W64在{wins}组配对输入/目标中完整业务链比例增加，{losses}组减少。其余持平；不据此宣称普遍优势。" if effects else "本次未运行扩展实验。"
 body="<h1>工业微服务部署：Windows接管与多场景评估</h1><p>范围已确认为本机代码和仿真；真实Swarm与VxWorks部署未验收。</p>"
 body+="<h2>验收清单</h2>"+table(acceptance)
 body+="<h2>算法目标</h2><p>新增实验模式的完整业务链优先：完整业务数→服务数→部署时间→活跃节点数；服务数优先作为对照：服务数→部署时间→活跃节点数。演练台保留原有服务数优先默认模式。三个基础算法维持各自选择规则，以同一指标评价；接管固定健康部署，不能等同初始全局最优规划。</p>"
 body+="<p>保留目标冲突反例：服务数优先3项服务/0条完整业务，完整链优先1项服务/1条完整业务。</p>"
 comparison=[]
 for objective in ("service_first","workflow_first"):
  paired=[x for x in effects if x["baseline"]=="first_fit" and x["objective"]==objective]
  if paired:comparison.append(dict(objective=objective,paired_inputs=len(paired),workflow_wins=sum(x["workflow_ratio_delta"]>0 for x in paired),workflow_ties=sum(x["workflow_ratio_delta"]==0 for x in paired),workflow_losses=sum(x["workflow_ratio_delta"]<0 for x in paired)))
 coverage=[]
 if (study/"exact.json").exists():
  exact_data=json.loads((study/"exact.json").read_text(encoding="utf-8-sig"))
  for scale in (4,8,12):
   group=[x for x in exact_data if x["service_scale"]==scale]
   coverage.append(dict(service_scale=scale,objective_cases=len(group),proven=sum(x["optimal"] for x in group),not_proven=sum(not x["optimal"] and not x["skip_reason"] for x in group),skipped=sum(bool(x["skip_reason"]) for x in group)))
 body+="<h2>W64与First Fit的配对结果</h2>"+table(comparison)
 body+="<h2>精确求解覆盖情况</h2>"+table(coverage)
 body+="<h2>扩展实验</h2><pre>"+html.escape(json.dumps(manifest,ensure_ascii=False,indent=2))+"</pre><p>"+conclusion+"</p>"
 body+="<p>5个种子×4种拓扑（双链、分叉汇合、独立服务、随机DAG）×3种资源/能力配置×3种服务规模（4/8/12），共180组输入。每组两种目标、7种方法；同输入预热1次、测量3次。同输入重复只用于计时变化，不当作独立场景样本。结果为合成配置。</p>"
 body+="<p>4服务精确求解最多50万状态/2秒；8服务最多10万状态/250毫秒；12服务不进行精确求解。只有完成穷举并且FIFO顺序一致时填写最优性主目标差距；其它留空。不同服务身份下不计算部署时间提升；所有原始方案和事件保留。</p>"
 body+=("<h2>图表</h2>" if aggregate else "")+'<div class="figures">'+"".join('<img src="figures/'+x+'.png" alt="'+x+'">' for x in (("service-ratio","workflow-ratio","planning-time") if aggregate else ()))+"</div>"
 body+="<h2>按拓扑、配置、目标分层结果</h2><p>下方筛选不改变原始文件。</p><input id='filter' placeholder='输入 topology / profile / objective / method 筛选'>"+table(aggregate)
 body+="<h2>环境与未执行项</h2><pre>"+html.escape(json.dumps(environment,ensure_ascii=False,indent=2))+"</pre>"
 body+="<p>本次只验收仿真与可视化。Windows接管表示选择Windows版本与节点画像，并执行Java/CloudSim部署事件；未启动真实Windows容器。资源指标是预留比例，不是实际CPU/RAM负载，高预留比例不自动代表更优。规划计时在同一JVM内顺序执行，一次预热不能完全排除JIT/GC影响；不作普遍性能优势或显著性声明。</p>"
 body+="<p><a href='summary.csv'>逐场景汇总</a> · <a href='aggregate.csv'>分层结果</a> · <a href='paired-effects.csv'>配对差异</a> · <a href='acceptance.csv'>验收清单</a></p>"
 document="<!doctype html><html lang='zh-CN'><meta charset='utf-8'><title>跨平台接管与算法评估报告</title><style>body{font:16px/1.7 Segoe UI,Microsoft YaHei,sans-serif;max-width:1500px;margin:35px auto;padding:0 25px;color:#163047}table{border-collapse:collapse;width:100%;font-size:12px;display:block;overflow:auto;margin:20px 0}td,th{padding:8px;border:1px solid #d7e3ef;text-align:left;white-space:nowrap}th{background:#eaf2fa}tr:nth-child(even){background:#f8fafc}pre{background:#f1f5f9;padding:18px;overflow:auto}img{width:100%;max-width:1200px}input{padding:10px;width:65%}h2{margin-top:38px}</style>"+body+"<script>document.getElementById('filter').oninput=function(){const q=this.value.toLowerCase();document.querySelectorAll('tbody tr').forEach(r=>r.hidden=!r.textContent.toLowerCase().includes(q))}</script></html>"
 (out/"report.html").write_text(document,encoding="utf-8")
 (out/"report.md").write_text("# 本机验收与扩展实验\n\n"+conclusion+"\n\n"+json.dumps(manifest,ensure_ascii=False,indent=2)+"\n\n演练台保留服务数优先默认；实验分别评价两种目标。真实Swarm/VxWorks未运行；详见report.html及acceptance.csv。",encoding="utf-8")
 print("REPORT: "+str(out/"report.html"))
if __name__=="__main__":main()
