package org.example.iiot.scenario;

import java.util.ArrayList;
import java.util.List;
import org.example.iiot.model.*;

public final class ScenarioFactory {

    private ScenarioFactory() {}

    public static List<NodeSpec> pressureNodes() {
        return List.of(
                new NodeSpec(
                        "linux-01", OsType.LINUX,
                        2, 1500, 1536, 100
                ),
                new NodeSpec(
                        "linux-02", OsType.LINUX,
                        1, 1000, 512, 50
                ),
                new NodeSpec(
                        "win-01", OsType.WINDOWS,
                        2, 1250, 1792, 100
                ),
                new NodeSpec(
                        "win-02", OsType.WINDOWS,
                        1, 1000, 512, 50
                ),
                new NodeSpec(
                        "vx-01", OsType.VXWORKS,
                        1, 500, 256, 20
                ),
                new NodeSpec(
                        "vx-02", OsType.VXWORKS,
                        1, 300, 128, 10
                )
        );
    }

    public static List<ServiceSpec> replicateChains(
            List<ServiceSpec> template,
            int chainCount
    ) {
        if (chainCount <= 0) {
            throw new IllegalArgumentException(
                    "Chain count must be positive."
            );
        }

        List<ServiceSpec> result = new ArrayList<>();

        for (int chain = 1; chain <= chainCount; chain++) {
            String suffix = "-c" + chain;

            for (ServiceSpec service : template) {
                List<String> dependencies =
                        service.dependencies().stream()
                                .map(id -> id + suffix)
                                .toList();

                List<ServiceVariant> variants =
                        service.variants().stream()
                                .map(v -> new ServiceVariant(
                                        v.id() + suffix,
                                        v.os(),
                                        v.cpuMips(),
                                        v.memoryMiB(),
                                        v.packageMiB(),
                                        v.startupSeconds()
                                ))
                                .toList();

                result.add(new ServiceSpec(
                        service.id() + suffix,
                        dependencies,
                        variants
                ));
            }
        }

        return List.copyOf(result);
    }
}