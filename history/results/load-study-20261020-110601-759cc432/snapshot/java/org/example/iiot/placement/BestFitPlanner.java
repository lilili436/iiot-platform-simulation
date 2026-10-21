package org.example.iiot.placement;

import java.util.*;
import org.example.iiot.model.*;
import org.example.iiot.placement.FirstFitPlanner.Assignment;
import org.example.iiot.placement.FirstFitPlanner.Result;

public final class BestFitPlanner {

    private BestFitPlanner() {}

    public static Result plan(
            List<NodeSpec> nodes, List<ServiceSpec> services
    ) {
        Set<String> nodeIds = new HashSet<>();

        for (NodeSpec node : nodes) {
            if (!nodeIds.add(node.id())) {
                throw new IllegalArgumentException(
                        "Duplicate node: " + node.id()
                );
            }
        }

        Set<String> seen = new HashSet<>();

        for (ServiceSpec service : services) {
            if (seen.contains(service.id())) {
                throw new IllegalArgumentException(
                        "Duplicate service: " + service.id()
                );
            }

            if (!seen.containsAll(service.dependencies())) {
                throw new IllegalArgumentException(
                        "Put dependencies before service: " + service.id()
                );
            }

            seen.add(service.id());
        }

        double[] usedCpu = new double[nodes.size()];
        long[] usedMemory = new long[nodes.size()];

        Set<String> accepted = new HashSet<>();
        List<Assignment> assignments = new ArrayList<>();
        Map<String, String> rejections = new LinkedHashMap<>();

        for (ServiceSpec service : services) {
            if (!accepted.containsAll(service.dependencies())) {
                rejections.put(service.id(), "DEPENDENCY_REJECTED");
                continue;
            }

            Assignment selected = null;
            int selectedIndex = -1;
            double bestScore = Double.POSITIVE_INFINITY;

            for (int j = 0; j < nodes.size(); j++) {
                NodeSpec node = nodes.get(j);

                for (ServiceVariant variant : service.variants()) {
                    if (!CompatibilityChecker.canDeploy(variant, node)) {
                        continue;
                    }

                    double nextCpu = usedCpu[j] + variant.cpuMips();
                    long nextMemory = usedMemory[j] + variant.memoryMiB();

                    if (nextCpu > node.totalMips()
                            || nextMemory > node.memoryMiB()) {
                        continue;
                    }

                    double cpuRemaining =
                            (node.totalMips() - nextCpu)
                                    / node.totalMips();

                    double memoryRemaining =
                            (node.memoryMiB() - nextMemory)
                                    / (double) node.memoryMiB();

                    double score =
                            (cpuRemaining + memoryRemaining) / 2.0;

                    if (score < bestScore) {
                        bestScore = score;
                        selectedIndex = j;

                        selected = new Assignment(
                                service.id(), variant, node
                        );
                    }
                }
            }

            if (selected == null) {
                rejections.put(service.id(), "NO_FEASIBLE_PLACEMENT");
            } else {
                usedCpu[selectedIndex] +=
                        selected.variant().cpuMips();

                usedMemory[selectedIndex] +=
                        selected.variant().memoryMiB();

                assignments.add(selected);
                accepted.add(service.id());
            }
        }

        return new Result(assignments, rejections);
    }
}