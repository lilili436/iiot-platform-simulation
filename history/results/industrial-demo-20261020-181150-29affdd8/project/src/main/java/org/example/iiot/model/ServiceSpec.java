package org.example.iiot.model;

import java.util.List;

public record ServiceSpec(
        String id,
        List<String> dependencies,
        List<ServiceVariant> variants
) {
    public ServiceSpec {
        if (id == null || id.isBlank()) {
            throw new IllegalArgumentException("Service id is required.");
        }

        dependencies = List.copyOf(dependencies);
        variants = List.copyOf(variants);

        if (variants.isEmpty()) {
            throw new IllegalArgumentException(
                    "A service needs at least one platform variant."
            );
        }
    }
}