package org.example.iiot.placement;

import java.util.*;
import org.example.iiot.model.*;

public final class FirstFitPlanner {
    private FirstFitPlanner() {}

    public record Assignment(
            String serviceId, ServiceVariant variant, NodeSpec node
    ) {}

    public record Result(
            List<Assignment> assignments,
            Map<String, String> rejections
    ) {
        public Result {
            assignments = List.copyOf(assignments);
            rejections = Collections.unmodifiableMap(
                    new LinkedHashMap<>(rejections)
            );
        }
    }

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

        // Input services must be ordered after their dependencies.
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

            for (int j = 0; j < nodes.size() && selected == null; j++) {
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

                    usedCpu[j] = nextCpu;
                    usedMemory[j] = nextMemory;

                    selected = new Assignment(
                            service.id(), variant, node
                    );
                    break;
                }
            }

            if (selected == null) {
                rejections.put(service.id(), "NO_FEASIBLE_PLACEMENT");
            } else {
                assignments.add(selected);
                accepted.add(service.id());
            }
        }

        return new Result(assignments, rejections);
    }
}