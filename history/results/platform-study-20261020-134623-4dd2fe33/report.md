# 平台能力约束与部署审计
已完成32次运行。16/16项对照核查通过。mixed场景关闭能力门控时，8/8组存在声明能力违规；启用完整门控后，所有组零违规：True。合规就绪还要求全部上游依赖合规；数量减少不自动代表算法退化，数量增加也不自动代表实际平台可运行。

每组仅运行一次；规划耗时中位数等于本次观测，尚未验证重复一致性。

| 链数 | 场景 | 门控 | 算法 | 模型就绪 | 合规就绪 | 模型链 | 合规链 | 违规项 | 依赖阻断 | 部署/s | 规划/ms |
|---|---|---|---|---|---|---|---|---|---|---|---|
| 3 | uniform | base | first_fit | 8/12 | 8/12 | 1/3 | 1/3 | 0 | 0 | 8.560 | 1.616 |
| 3 | uniform | base | round_robin | 10/12 | 10/12 | 2/3 | 2/3 | 0 | 0 | 7.020 | 1.499 |
| 3 | uniform | base | best_fit | 10/12 | 10/12 | 2/3 | 2/3 | 0 | 0 | 6.920 | 24.374 |
| 3 | uniform | base | beam_search | 10/12 | 10/12 | 2/3 | 2/3 | 0 | 0 | 4.390 | 39.197 |
| 3 | uniform | full | first_fit | 8/12 | 8/12 | 1/3 | 1/3 | 0 | 0 | 8.560 | 19.496 |
| 3 | uniform | full | round_robin | 10/12 | 10/12 | 2/3 | 2/3 | 0 | 0 | 7.020 | 3.093 |
| 3 | uniform | full | best_fit | 10/12 | 10/12 | 2/3 | 2/3 | 0 | 0 | 6.920 | 2.794 |
| 3 | uniform | full | beam_search | 10/12 | 10/12 | 2/3 | 2/3 | 0 | 0 | 4.390 | 55.578 |
| 3 | mixed | base | first_fit | 8/12 | 7/12 | 1/3 | 1/3 | 1 | 0 | 8.560 | 1.500 |
| 3 | mixed | base | round_robin | 10/12 | 2/12 | 2/3 | 0/3 | 4 | 4 | 7.020 | 2.138 |
| 3 | mixed | base | best_fit | 10/12 | 2/12 | 2/3 | 0/3 | 4 | 4 | 6.920 | 3.846 |
| 3 | mixed | base | beam_search | 10/12 | 4/12 | 2/3 | 1/3 | 4 | 2 | 4.390 | 61.560 |
| 3 | mixed | full | first_fit | 8/12 | 8/12 | 1/3 | 1/3 | 0 | 0 | 7.560 | 2.098 |
| 3 | mixed | full | round_robin | 8/12 | 8/12 | 1/3 | 1/3 | 0 | 0 | 6.170 | 2.013 |
| 3 | mixed | full | best_fit | 7/12 | 7/12 | 1/3 | 1/3 | 0 | 0 | 4.150 | 2.606 |
| 3 | mixed | full | beam_search | 8/12 | 8/12 | 1/3 | 1/3 | 0 | 0 | 3.700 | 51.525 |
| 6 | uniform | base | first_fit | 13/24 | 13/24 | 1/6 | 1/6 | 0 | 0 | 8.560 | 1.840 |
| 6 | uniform | base | round_robin | 13/24 | 13/24 | 2/6 | 2/6 | 0 | 0 | 7.220 | 1.901 |
| 6 | uniform | base | best_fit | 13/24 | 13/24 | 2/6 | 2/6 | 0 | 0 | 7.320 | 2.218 |
| 6 | uniform | base | beam_search | 13/24 | 13/24 | 2/6 | 2/6 | 0 | 0 | 4.390 | 45.893 |
| 6 | uniform | full | first_fit | 13/24 | 13/24 | 1/6 | 1/6 | 0 | 0 | 8.560 | 2.631 |
| 6 | uniform | full | round_robin | 13/24 | 13/24 | 2/6 | 2/6 | 0 | 0 | 7.220 | 2.794 |
| 6 | uniform | full | best_fit | 13/24 | 13/24 | 2/6 | 2/6 | 0 | 0 | 7.320 | 5.049 |
| 6 | uniform | full | beam_search | 13/24 | 13/24 | 2/6 | 2/6 | 0 | 0 | 4.390 | 79.775 |
| 6 | mixed | base | first_fit | 13/24 | 8/24 | 1/6 | 1/6 | 4 | 1 | 8.560 | 1.750 |
| 6 | mixed | base | round_robin | 13/24 | 5/24 | 2/6 | 0/6 | 4 | 4 | 7.220 | 1.948 |
| 6 | mixed | base | best_fit | 13/24 | 5/24 | 2/6 | 0/6 | 4 | 4 | 7.320 | 1.848 |
| 6 | mixed | base | beam_search | 13/24 | 6/24 | 2/6 | 1/6 | 5 | 2 | 4.390 | 48.007 |
| 6 | mixed | full | first_fit | 10/24 | 10/24 | 1/6 | 1/6 | 0 | 0 | 7.960 | 2.400 |
| 6 | mixed | full | round_robin | 11/24 | 11/24 | 1/6 | 1/6 | 0 | 0 | 6.970 | 3.166 |
| 6 | mixed | full | best_fit | 7/24 | 7/24 | 1/6 | 1/6 | 0 | 0 | 4.150 | 2.698 |
| 6 | mixed | full | beam_search | 11/24 | 11/24 | 1/6 | 1/6 | 0 | 0 | 4.280 | 73.426 |

## 指标范围
本模块使用固定合成声明。X86_64、ARM64、容器/RTP、API、驱动及安全标签均为模型字段。SIGNED_PACKAGE/TLS_NETWORK/TRUSTED_NODE只表示集合约束，未执行验签、TLS连接或可信启动。未探测真实设备、ABI、驱动或操作系统版本。原READY仅为离散事件状态；合规READY为该状态叠加声明和依赖闭包检查。部署时间仅覆盖已接纳服务，不能因任务减少直接宣称提速。资源预留不等于实测利用率；独立JVM未排除JIT/预热，计时仅作描述；不做显著性、真实跨平台成功率或普遍最优结论。

逐项审计见audits/，配对差异见paired-mode-effects.csv，对照检查见control-checks.csv。
Material Passport: academic-research-suite / experiment-agent; code-experiment; 2026-10-20; LOCAL_GENERATED_DESCRIPTIVE; platform-study-v1. 人工阅读标记未声明。