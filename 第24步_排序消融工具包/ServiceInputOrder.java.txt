package org.example.iiot.scenario;

import java.util.*;
import org.example.iiot.model.ServiceSpec;

public final class ServiceInputOrder {
    private ServiceInputOrder() {}

    public static List<ServiceSpec> byLevel(List<ServiceSpec> services) {
        Map<String, Integer> levels = new HashMap<>();

        for (ServiceSpec service : services) {
            if (levels.containsKey(service.id())) {
                throw new IllegalArgumentException("Duplicate service: " + service.id());
            }
            int level = 0;
            for (String dependency : service.dependencies()) {
                Integer upstream = levels.get(dependency);
                if (upstream == null) {
                    throw new IllegalArgumentException(
                            "Put dependencies before service: " + service.id()
                    );
                }
                level = Math.max(level, upstream + 1);
            }
            levels.put(service.id(), level);
        }

        return services.stream()
                .sorted(Comparator.comparingInt(s -> levels.get(s.id())))
                .toList();
    }
}
