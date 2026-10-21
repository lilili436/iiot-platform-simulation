package org.example.iiot.model;

public record NodeSpec(
        String id,
        OsType os,
        int cpuCores,
        double mipsPerCore,
        int memoryMiB,
        double bandwidthMiBps
) {
    public NodeSpec {
        if (id == null || id.isBlank() || os == null) {
            throw new IllegalArgumentException("Node id and OS are required.");
        }

        if (cpuCores <= 0 || memoryMiB <= 0
                || !Double.isFinite(mipsPerCore) || mipsPerCore <= 0
                || !Double.isFinite(bandwidthMiBps) || bandwidthMiBps <= 0) {
            throw new IllegalArgumentException("Node resources must be positive.");
        }
    }

    public double totalMips() {
        return cpuCores * mipsPerCore;
    }
}