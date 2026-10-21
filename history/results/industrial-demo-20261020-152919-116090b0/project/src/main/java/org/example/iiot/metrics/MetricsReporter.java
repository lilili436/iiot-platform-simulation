package org.example.iiot.metrics;

import java.io.IOException;
import java.io.UncheckedIOException;
import java.nio.charset.StandardCharsets;
import java.nio.file.*;
import java.util.*;

import org.example.iiot.model.*;
import org.example.iiot.placement.FirstFitPlanner;
import org.example.iiot.simulation.DeploymentSimulation;

public final class MetricsReporter {

    private MetricsReporter() {}

    private static double ratio(double used, double capacity) {
        // A zero denominator means the ratio is not applicable.
        return capacity > 0 ? used / capacity : Double.NaN;
    }

    public static void report(
	    String scenario,
	    String algorithm,
            List<NodeSpec> nodes,
            List<ServiceSpec> services,
            FirstFitPlanner.Result plan,
            DeploymentSimulation deployment,
            double plannerMillis
    ) {
        int requested = services.size();
        int accepted = plan.assignments().size();
        int ready = deployment.readyCount();

	var workflows = WorkflowMetrics.summarize(
        	services,
        	deployment.readyServiceIds()
	);

	double workflowReadyRatio = ratio(
        	workflows.ready(),
        	workflows.requested()
	);

        Set<String> activeIds = new HashSet<>();
        double reservedCpu = 0;
        long reservedMemory = 0;

        for (var assignment : plan.assignments()) {
            activeIds.add(assignment.node().id());
            reservedCpu += assignment.variant().cpuMips();
            reservedMemory += assignment.variant().memoryMiB();
        }

        double allCpu = 0;
        double activeCpu = 0;
        long allMemory = 0;
        long activeMemory = 0;

        for (NodeSpec node : nodes) {
            allCpu += node.totalMips();
            allMemory += node.memoryMiB();

            if (activeIds.contains(node.id())) {
                activeCpu += node.totalMips();
                activeMemory += node.memoryMiB();
            }
        }

        double admission = ratio(accepted, requested);
        double readyRatio = ratio(ready, requested);

        double cpuAll = ratio(reservedCpu, allCpu);
        double memoryAll = ratio(reservedMemory, allMemory);

        double cpuActive = ratio(reservedCpu, activeCpu);
        double memoryActive = ratio(reservedMemory, activeMemory);

        double combinedActive =
                (cpuActive + memoryActive) / 2.0;

        System.out.printf(
                Locale.ROOT,
                """
                
                === Metrics summary ===
                Requested: %d | Accepted: %d | Ready: %d
                Active nodes: %d/%d
                Model admission: %.2f%%
                Simulated ready ratio: %.2f%%
                CPU reserved (all nodes): %.2f%%
                RAM reserved (all nodes): %.2f%%
                CPU reserved (active nodes): %.2f%%
                RAM reserved (active nodes): %.2f%%
                Combined reserved (active nodes): %.2f%%
                Deployment simulation time: %.3f s
                Planner wall time: %.3f ms
                """,
                requested, accepted, ready,
                activeIds.size(), nodes.size(),
                admission * 100, readyRatio * 100,
                cpuAll * 100, memoryAll * 100,
                cpuActive * 100, memoryActive * 100,
                combinedActive * 100,
                deployment.deploymentSeconds(), plannerMillis
        );

	System.out.printf(
        	Locale.ROOT,
        	"Workflows requested: %d | Fully ready: %d%n"
                	+ "Workflow ready ratio: %.2f%%%n",
        	workflows.requested(),
        	workflows.ready(),
        	workflowReadyRatio * 100
	);
        String header = String.join(",",
		"scenario", "algorithm", "requested", "accepted", "ready",
                "active_nodes", "admission_ratio", "ready_ratio",
                "cpu_reserved_ratio_all", "ram_reserved_ratio_all",
                "cpu_reserved_ratio_active", "ram_reserved_ratio_active",
                "combined_reserved_ratio_active",
                "deployment_sim_seconds", "planner_wall_ms",
		"workflow_requested", "workflow_ready", "workflow_ready_ratio"
        ) + "\n";

        String row = String.format(
                Locale.ROOT,
                "%s,%s,%d,%d,%d,%d,%.9f,%.9f,%.9f,%.9f,%.9f,%.9f,%.9f,%.9f,%.6f"
                	+ ",%d,%d,%.9f%n",
		scenario, algorithm,
                requested, accepted, ready, activeIds.size(),
                admission, readyRatio, cpuAll, memoryAll,
                cpuActive, memoryActive, combinedActive,
                deployment.deploymentSeconds(), plannerMillis,
        	workflows.requested(), workflows.ready(), workflowReadyRatio
        );

        try {
            Path directory = Path.of("results");
            Files.createDirectories(directory);

            Path output = Files.createTempFile(
                    directory, 
		    scenario + "-" + algorithm + "-",
		    ".csv"
            );

            Files.writeString(
                    output, header + row, StandardCharsets.UTF_8
            );

            System.out.println(
                    "CSV saved: " + output.toAbsolutePath()
            );

        } catch (IOException e) {
            throw new UncheckedIOException(
                    "Cannot save metrics.", e
            );
        }
    }
}