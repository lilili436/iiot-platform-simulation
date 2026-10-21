package org.example.iiot;

import org.example.iiot.placement.ScarcityOrder;

import org.example.iiot.placement.BeamSearchPlanner;

import java.util.Calendar;
import java.util.List;

import org.cloudbus.cloudsim.core.CloudSim;
import org.example.iiot.model.NodeSpec;
import org.example.iiot.model.OsType;

import org.example.iiot.model.ServiceSpec;
import org.example.iiot.model.ServiceVariant;

import java.util.ArrayList;
import org.example.iiot.placement.CompatibilityChecker;

import org.example.iiot.placement.FirstFitPlanner;

import org.example.iiot.simulation.DeploymentSimulation;

import org.example.iiot.metrics.MetricsReporter;

import org.example.iiot.placement.RoundRobinPlanner;

import org.example.iiot.scenario.ScenarioFactory;

import org.example.iiot.placement.BestFitPlanner;

public class SimulationMain {

    public static void main(String[] args) {
        CloudSim.init(1, Calendar.getInstance(), false);
	if (args.length > 3) {
    		throw new IllegalArgumentException(
            	"Usage: <algorithm> <scenario> [chainCount]"
    		);
	}

	String scenario = args.length > 1 ? args[1] : "demo";

	if (!scenario.equals("demo") && !scenario.equals("pressure")) {
    		throw new IllegalArgumentException(
            		"Unknown scenario: " + scenario
    		);
	}

	int chainCount = scenario.equals("pressure") ? 3 : 1;

	if (args.length > 2) {
    		if (!scenario.equals("pressure")) {
        		throw new IllegalArgumentException(
                		"chainCount is supported only for pressure."
        		);
    		}

    		try {
        		chainCount = Integer.parseInt(args[2]);
    		} catch (NumberFormatException e) {
        		throw new IllegalArgumentException(
                		"chainCount must be a positive integer.", e
        		);
    		}

    		if (chainCount <= 0) {
        		throw new IllegalArgumentException(
                		"chainCount must be a positive integer."
        		);
    		}
	}

	System.out.println("Scenario: " + scenario);
	System.out.println("Chains: " + chainCount);

        List<NodeSpec> nodes = List.of(
                new NodeSpec(
                        "linux-01", OsType.LINUX,
                        4, 2000, 8192, 100
                ),
                new NodeSpec(
                        "linux-02", OsType.LINUX,
                        2, 1500, 4096, 50
                ),
                new NodeSpec(
                        "win-01", OsType.WINDOWS,
                        4, 2000, 8192, 100
                ),
                new NodeSpec(
                        "win-02", OsType.WINDOWS,
                        2, 1500, 4096, 50
                ),
                new NodeSpec(
                        "vx-01", OsType.VXWORKS,
                        2, 1000, 1024, 20
                ),
                new NodeSpec(
                        "vx-02", OsType.VXWORKS,
                        1, 800, 512, 10
                )
        );

        System.out.println();
	if (scenario.equals("pressure")) {
    		nodes = ScenarioFactory.pressureNodes();
	}
        System.out.println("=== Simulated node inventory ===");

        System.out.printf(
                "%-10s %-10s %5s %10s %10s %12s%n",
                "ID", "OS", "Cores", "TotalMIPS", "RAM_MiB", "BW_MiBps"
        );

        for (NodeSpec node : nodes) {
            System.out.printf(
                    "%-10s %-10s %5d %10.0f %10d %12.1f%n",
                    node.id(),
                    node.os(),
                    node.cpuCores(),
                    node.totalMips(),
                    node.memoryMiB(),
                    node.bandwidthMiBps()
            );
        }

        System.out.println("Total nodes: " + nodes.size());
	List<ServiceSpec> services = List.of(
        	new ServiceSpec(
                	"collect",
                	List.of(),
                	List.of(
                        	new ServiceVariant(
                                	"collect-linux", OsType.LINUX,
                                	300, 128, 12, 0.4
                        	),
                        	new ServiceVariant(
                                	"collect-win", OsType.WINDOWS,
                                	400, 192, 20, 0.6
                        	),
                        	new ServiceVariant(
                                	"collect-vx", OsType.VXWORKS,
                                	100, 32, 2, 0.1
                        	)
                	)
        	),
        	new ServiceSpec(
                	"preprocess",
                	List.of("collect"),
                	List.of(
                        	new ServiceVariant(
                                	"preprocess-linux", OsType.LINUX,
                                	800, 512, 30, 0.8
                        	),
                        	new ServiceVariant(
                                	"preprocess-win", OsType.WINDOWS,
                                	900, 512, 45, 1.0
                        	),
                        	new ServiceVariant(
                                	"preprocess-vx", OsType.VXWORKS,
                                	300, 128, 4, 0.2
                        	)
                	)
        	),
        	new ServiceSpec(
                	"detect",
                	List.of("preprocess"),
                	List.of(
                        	new ServiceVariant(
                                	"detect-linux", OsType.LINUX,
                                	2000, 1024, 100, 1.2
                        	),
                        	new ServiceVariant(
                                	"detect-win", OsType.WINDOWS,
                                	2200, 1536, 150, 1.5
                        	)
                	)
        	),
        	new ServiceSpec(
                	"alert",
                	List.of("detect"),
                	List.of(
                        	new ServiceVariant(
                                	"alert-linux", OsType.LINUX,
                                	200, 128, 10, 0.3
                        	),
                        	new ServiceVariant(
                                	"alert-win", OsType.WINDOWS,
                                	250, 192, 15, 0.4
                        	),
                        	new ServiceVariant(
                                	"alert-vx", OsType.VXWORKS,
                                	100, 32, 1, 0.1
                        	)
                	)
        	)
	);

	System.out.println();
	if (scenario.equals("pressure")) {
    		services = ScenarioFactory.replicateChains(services, chainCount);
	}
	System.out.println("=== Service inventory ===");

	int totalVariants = 0;

	for (ServiceSpec service : services) {
    		System.out.printf(
            		"Service: %s | Depends on: %s%n",
            		service.id(),
            		service.dependencies()
    		);

    		for (ServiceVariant variant : service.variants()) {
        		System.out.printf(
                		"  %-20s OS=%-8s CPU=%6.0f RAM=%4d Package=%5.1f Start=%.1fs%n",
                		variant.id(),
                		variant.os(),
                		variant.cpuMips(),
                		variant.memoryMiB(),
                		variant.packageMiB(),
                		variant.startupSeconds()
        		);

        		totalVariants++;
    		}
	}

	System.out.println("Total services: " + services.size());
	System.out.println("Total variants: " + totalVariants);
	System.out.println();
	System.out.println("=== Compatible placements ===");

	for (ServiceSpec service : services) {
    		List<String> candidates = new ArrayList<>();

    		for (ServiceVariant variant : service.variants()) {
        		for (NodeSpec node : nodes) {
            			if (CompatibilityChecker.canDeploy(variant, node)) {
                			candidates.add(
                        			node.id() + " [" + variant.id() + "]"
                			);
            			}
        		}
    		}

    		System.out.printf(
            		"Service: %s | Candidate placements: %d%n",
            		service.id(),
            		candidates.size()
    		);

    		for (String candidate : candidates) {
        		System.out.println("  " + candidate);
    		}
	}

	// Independent examples for checking rejection reasons.
	System.out.println();
	System.out.println();
	System.out.println("=== Scarcity order ===");

	List<ServiceSpec> scarcityOrdered =
        	ScarcityOrder.order(nodes, services);

	for (ServiceSpec service : scarcityOrdered) {
    		System.out.printf(
            		"%-14s candidates=%d depends=%s%n",
            		service.id(),
            		ScarcityOrder.candidateNodeCount(service, nodes),
            		service.dependencies()
    		);
	}
	System.out.println("=== Rejection examples ===");

	ServiceVariant probeVariant = new ServiceVariant(
        	"probe-linux", OsType.LINUX,
        	200, 128, 1, 0.1
	);

	NodeSpec smallNode = new NodeSpec(
        	"probe-small", OsType.LINUX,
        	1, 100, 64, 10
	);

	NodeSpec wrongOsNode = new NodeSpec(
        	"probe-windows", OsType.WINDOWS,
        	1, 1000, 1024, 10
	);

	System.out.println(
        	"Resource rejection: "
                	+ CompatibilityChecker.rejectionReasons(
                        	probeVariant, smallNode
                	)
	);

	System.out.println(
        	"OS rejection: "
                	+ CompatibilityChecker.rejectionReasons(
                        	probeVariant, wrongOsNode
                	)
	);
	System.out.println();
	String algorithm = args.length == 0 ? "first_fit" : args[0];

	System.out.println(
        	"=== Placement plan: " + algorithm + " ==="
	);

	long planningStarted = System.nanoTime();

	var plan = switch (algorithm) {
    		case "first_fit" ->
            		FirstFitPlanner.plan(nodes, services);

    		case "round_robin" ->
            		RoundRobinPlanner.plan(nodes, services);

		case "best_fit" ->
            		BestFitPlanner.plan(nodes, services);

		case "beam_search" ->
            		BeamSearchPlanner.plan(nodes, services, 64);

    		default -> throw new IllegalArgumentException(
            		"Unknown algorithm: " + algorithm
    		);
	};

	double plannerMillis =
        	(System.nanoTime() - planningStarted) / 1_000_000.0;

	for (var assignment : plan.assignments()) {
    		System.out.printf(
            		"%-12s -> %-10s | Variant: %s%n",
            		assignment.serviceId(),
            		assignment.node().id(),
            		assignment.variant().id()
    		);
	}

	plan.rejections().forEach((serviceId, reason) ->
        	System.out.println(
                	"REJECTED: " + serviceId + " | " + reason
        	)
	);

	System.out.printf(
        	"Accepted: %d | Rejected: %d%n",
        	plan.assignments().size(),
        	plan.rejections().size()
	);

	System.out.println();
	System.out.println("=== Reserved node resources ===");

	for (NodeSpec node : nodes) {
    		double reservedCpu = plan.assignments().stream()
            		.filter(a -> a.node().id().equals(node.id()))
            		.mapToDouble(a -> a.variant().cpuMips())
            		.sum();

    		long reservedMemory = plan.assignments().stream()
            		.filter(a -> a.node().id().equals(node.id()))
            		.mapToLong(a -> a.variant().memoryMiB())
            		.sum();

    		System.out.printf(
            		"%-10s CPU: %.0f/%.0f MIPS | RAM: %d/%d MiB%n",
            		node.id(),
            		reservedCpu,
            		node.totalMips(),
            		reservedMemory,
            		node.memoryMiB()
    		);
	}
	System.out.println();
	System.out.println("=== Deployment events ===");

	var deployment = new DeploymentSimulation(
        	"Deployment", services, plan
	);

	CloudSim.startSimulation();

	if (deployment.readyCount() != plan.assignments().size()) {
    		throw new IllegalStateException(
            		"Some accepted services did not become ready."
    		);
	}

	System.out.printf(
        	java.util.Locale.ROOT,
        	"Ready services: %d%nDeployment simulation time: %.3f s%n",
        	deployment.readyCount(),
        	deployment.deploymentSeconds()
	);
	MetricsReporter.report(
		scenario,
		algorithm,
        	nodes,
        	services,
        	plan,
        	deployment,
        	plannerMillis
	);
    }
}