package org.example.iiot.model;

public record ServiceVariant(
        String id,
        OsType os,
        double cpuMips,
        int memoryMiB,
        double packageMiB,
        double startupSeconds
) {
    public ServiceVariant {
        if (id == null || id.isBlank() || os == null) {
            throw new IllegalArgumentException("Variant id and OS are required.");
        }

        if (!Double.isFinite(cpuMips) || cpuMips <= 0
                || memoryMiB <= 0
                || !Double.isFinite(packageMiB) || packageMiB < 0
                || !Double.isFinite(startupSeconds) || startupSeconds < 0) {
            throw new IllegalArgumentException("Invalid variant resources.");
        }
    }
}