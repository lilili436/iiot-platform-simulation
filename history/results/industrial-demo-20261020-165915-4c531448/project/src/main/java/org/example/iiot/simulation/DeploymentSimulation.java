package org.example.iiot.simulation;

import java.util.*;
import org.cloudbus.cloudsim.core.*;
import org.example.iiot.model.ServiceSpec;
import org.example.iiot.placement.FirstFitPlanner;

public final class DeploymentSimulation extends SimEntity {

    private enum Tag implements CloudSimTags {
        TRANSFER_DONE, READY
    }

    private final Map<String, List<String>> dependencies =
            new HashMap<>();

    private final Map<String, Queue<FirstFitPlanner.Assignment>> queues =
            new LinkedHashMap<>();

    private final Set<String> busyNodes = new HashSet<>();

    private final Map<String, Double> readyTimes =
            new LinkedHashMap<>();

    private double submittedAt;
    private final List<Map<String,Object>> events = new ArrayList<>();
    public List<Map<String,Object>> events(){return List.copyOf(events);}

    public DeploymentSimulation(
            String name,
            List<ServiceSpec> services,
            FirstFitPlanner.Result plan
    ) {
        super(name);

        for (ServiceSpec service : services) {
            dependencies.put(
                    service.id(), service.dependencies()
            );
        }

        for (var assignment : plan.assignments()) {
            if (!dependencies.containsKey(assignment.serviceId())) {
                throw new IllegalArgumentException(
                        "Unknown service in plan."
                );
            }

            queues.computeIfAbsent(
                    assignment.node().id(),
                    key -> new ArrayDeque<>()
            ).add(assignment);
        }
    }

    @Override
    public void startEntity() {
        submittedAt = CloudSim.clock();
        startEligible();
    }

    private void startEligible() {
        for (var entry : queues.entrySet()) {
            String nodeId = entry.getKey();
            Queue<FirstFitPlanner.Assignment> queue =
                    entry.getValue();

            if (busyNodes.contains(nodeId) || queue.isEmpty()) {
                continue;
            }

            var assignment = queue.peek();

            if (!readyTimes.keySet().containsAll(
                    dependencies.get(assignment.serviceId())
            )) {
                continue;
            }

            queue.remove();
            busyNodes.add(nodeId);
            log("TRANSFER", assignment);

            double transferSeconds =
                    assignment.variant().packageMiB()
                            / assignment.node().bandwidthMiBps();

            schedule(
                    getId(),
                    transferSeconds,
                    Tag.TRANSFER_DONE,
                    assignment
            );
        }
    }

    @Override
    public void processEvent(SimEvent event) {
        var assignment =
                (FirstFitPlanner.Assignment) event.getData();

        if (event.getTag() == Tag.TRANSFER_DONE) {
            log("STARTUP", assignment);

            schedule(
                    getId(),
                    assignment.variant().startupSeconds(),
                    Tag.READY,
                    assignment
            );

        } else if (event.getTag() == Tag.READY) {
            readyTimes.put(
                    assignment.serviceId(), CloudSim.clock()
            );

            busyNodes.remove(assignment.node().id());

            log("READY", assignment);
            startEligible();

        } else {
            throw new IllegalArgumentException(
                    "Unknown deployment event."
            );
        }
    }

    private void log(
            String phase,
            FirstFitPlanner.Assignment assignment
    ) {
        events.add(Map.of("time",CloudSim.clock(),"phase",phase,"service",assignment.serviceId(),"node",assignment.node().id()));
        System.out.printf(
                Locale.ROOT,
                "t=%6.3fs %-8s %-12s @ %s%n",
                CloudSim.clock(),
                phase,
                assignment.serviceId(),
                assignment.node().id()
        );
    }

    public Set<String> readyServiceIds() {
    	return Set.copyOf(readyTimes.keySet());
    }
    public int readyCount() {
        return readyTimes.size();
    }

    public double deploymentSeconds() {
        double lastReady = readyTimes.values().stream()
                .mapToDouble(Double::doubleValue)
                .max()
                .orElse(submittedAt);

        return lastReady - submittedAt;
    }
}