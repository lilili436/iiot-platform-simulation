package org.example.iiot.metrics;

import java.util.*;
import org.example.iiot.model.ServiceSpec;

public final class WorkflowMetrics {
    private WorkflowMetrics() {}

    public record Counts(int requested, int ready) {}

    public static Counts summarize(
            List<ServiceSpec> services,
            Set<String> readyServiceIds
    ) {
        Map<String, Set<String>> graph = new LinkedHashMap<>();

        for (ServiceSpec service : services) {
            if (graph.putIfAbsent(
                    service.id(), new LinkedHashSet<>()
            ) != null) {
                throw new IllegalArgumentException(
                        "Duplicate service: " + service.id()
                );
            }
        }

        for (ServiceSpec service : services) {
            for (String dependency : service.dependencies()) {
                if (!graph.containsKey(dependency)) {
                    throw new IllegalArgumentException(
                            "Unknown dependency: " + dependency
                    );
                }

                graph.get(service.id()).add(dependency);
                graph.get(dependency).add(service.id());
            }
        }

        Set<String> visited = new HashSet<>();
        int requested = 0;
        int ready = 0;

        for (String start : graph.keySet()) {
            if (!visited.add(start)) {
                continue;
            }

            requested++;
            boolean complete = true;

            Deque<String> pending = new ArrayDeque<>();
            pending.add(start);

            while (!pending.isEmpty()) {
                String id = pending.removeFirst();

                if (!readyServiceIds.contains(id)) {
                    complete = false;
                }

                for (String neighbor : graph.get(id)) {
                    if (visited.add(neighbor)) {
                        pending.addLast(neighbor);
                    }
                }
            }

            if (complete) {
                ready++;
            }
        }

        return new Counts(requested, ready);
    }
}