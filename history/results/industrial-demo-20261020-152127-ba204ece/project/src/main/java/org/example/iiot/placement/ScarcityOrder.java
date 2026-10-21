package org.example.iiot.placement;

import java.util.*;
import org.example.iiot.model.*;

public final class ScarcityOrder {
    private ScarcityOrder() {}

    public static int candidateNodeCount(
            ServiceSpec service, List<NodeSpec> nodes
    ) {
        return (int) nodes.stream()
                .filter(node -> service.variants().stream()
                        .anyMatch(v -> CompatibilityChecker.canDeploy(v, node)))
                .map(NodeSpec::id)
                .distinct()
                .count();
    }

    public static List<ServiceSpec> order(
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

        Map<String, ServiceSpec> byId = new LinkedHashMap<>();
        Map<String, Integer> counts = new HashMap<>();

        for (ServiceSpec service : services) {
            if (byId.putIfAbsent(service.id(), service) != null) {
                throw new IllegalArgumentException(
                        "Duplicate service: " + service.id()
                );
            }

            counts.put(
                    service.id(),
                    candidateNodeCount(service, nodes)
            );
        }

        for (ServiceSpec service : services) {
            for (String dependency : service.dependencies()) {
                if (!byId.containsKey(dependency)) {
                    throw new IllegalArgumentException(
                            "Unknown dependency: " + dependency
                    );
                }
            }
        }

        List<ServiceSpec> remaining = new ArrayList<>(services);
        List<ServiceSpec> result = new ArrayList<>();
        Set<String> orderedIds = new HashSet<>();

        while (!remaining.isEmpty()) {
            ServiceSpec selected = null;
            int minimum = Integer.MAX_VALUE;

            for (ServiceSpec service : remaining) {
                if (!orderedIds.containsAll(service.dependencies())) {
                    continue;
                }

                int count = counts.get(service.id());

                if (selected == null || count < minimum) {
                    selected = service;
                    minimum = count;
                }
            }

            if (selected == null) {
                throw new IllegalArgumentException(
                        "Cyclic service dependencies."
                );
            }

            result.add(selected);
            orderedIds.add(selected.id());
            remaining.remove(selected);
        }

        return List.copyOf(result);
    }
}