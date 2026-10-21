package org.example.iiot.placement;

import java.util.ArrayList;
import java.util.List;

import org.example.iiot.model.NodeSpec;
import org.example.iiot.model.ServiceVariant;

public final class CompatibilityChecker {

    private CompatibilityChecker() {
    }

    public static List<String> rejectionReasons(
            ServiceVariant variant,
            NodeSpec node
    ) {
        List<String> reasons = new ArrayList<>();

        if (variant.os() != node.os()) {
            reasons.add(
                    "OS_MISMATCH: required=" + variant.os()
                            + ", actual=" + node.os()
            );
        }

        if (variant.cpuMips() > node.totalMips()) {
            reasons.add(
                    "CPU_INSUFFICIENT: required=" + variant.cpuMips()
                            + ", capacity=" + node.totalMips()
            );
        }

        if (variant.memoryMiB() > node.memoryMiB()) {
            reasons.add(
                    "MEMORY_INSUFFICIENT: required=" + variant.memoryMiB()
                            + ", capacity=" + node.memoryMiB()
            );
        }

        reasons.addAll(PlatformPolicy.activeRejectionReasons(variant, node));
        return List.copyOf(reasons);
    }

    public static boolean canDeploy(
            ServiceVariant variant,
            NodeSpec node
    ) {
        return rejectionReasons(variant, node).isEmpty();
    }
}