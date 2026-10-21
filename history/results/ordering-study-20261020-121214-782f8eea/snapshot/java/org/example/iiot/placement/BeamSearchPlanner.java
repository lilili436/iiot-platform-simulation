package org.example.iiot.placement;

import java.util.*;
import org.example.iiot.model.*;
import org.example.iiot.placement.FirstFitPlanner.Assignment;
import org.example.iiot.placement.FirstFitPlanner.Result;

public final class BeamSearchPlanner {
    private BeamSearchPlanner() {}

    private static final class State {
        final double[] cpu;
        final long[] memory;
        final double[] nodeReady;
        final Map<String, Double> ready;
        final List<Assignment> assignments;
        final Map<String, String> rejections;

        State(int nodeCount) {
            cpu = new double[nodeCount];
            memory = new long[nodeCount];
            nodeReady = new double[nodeCount];
            ready = new HashMap<>();
            assignments = new ArrayList<>();
            rejections = new LinkedHashMap<>();
        }

        State(State other) {
            cpu = other.cpu.clone();
            memory = other.memory.clone();
            nodeReady = other.nodeReady.clone();
            ready = new HashMap<>(other.ready);
            assignments = new ArrayList<>(other.assignments);
            rejections = new LinkedHashMap<>(other.rejections);
        }

        double seconds() {
            return Arrays.stream(nodeReady).max().orElse(0.0);
        }

        int activeNodes() {
            int count = 0;

            for (double used : cpu) {
                if (used > 0) count++;
            }

            return count;
        }
    }

    private static final Comparator<State> RANK =
            Comparator.<State>comparingInt(s -> s.assignments.size())
                    .reversed()
                    .thenComparingDouble(State::seconds)
                    .thenComparingInt(State::activeNodes);

    public static Result plan(
            List<NodeSpec> nodes,
            List<ServiceSpec> services,
            int beamWidth
    ) {
        return plan(nodes, services, beamWidth, true);
    }

    public static Result plan(
            List<NodeSpec> nodes,
            List<ServiceSpec> services,
            int beamWidth,
            boolean useScarcity
    ) {
        if (beamWidth <= 0) {
            throw new IllegalArgumentException(
                    "beamWidth must be positive."
            );
        }

        List<ServiceSpec> ordered = useScarcity
                ? ScarcityOrder.order(nodes, services)
                : checkedInputOrder(nodes, services);

        List<State> beam = List.of(new State(nodes.size()));

        for (ServiceSpec service : ordered) {
            List<State> expanded = new ArrayList<>();

            for (State state : beam) {
                if (!state.ready.keySet().containsAll(
                        service.dependencies()
                )) {
                    expanded.add(reject(
                            state, service, "DEPENDENCY_REJECTED"
                    ));
                    continue;
                }

                double dependencyReady = 0.0;

                for (String dependency : service.dependencies()) {
                    dependencyReady = Math.max(
                            dependencyReady,
                            state.ready.get(dependency)
                    );
                }

                boolean feasible = false;

                for (int j = 0; j < nodes.size(); j++) {
                    NodeSpec node = nodes.get(j);

                    for (ServiceVariant variant : service.variants()) {
                        if (!CompatibilityChecker.canDeploy(
                                variant, node
                        )) {
                            continue;
                        }

                        double nextCpu =
                                state.cpu[j] + variant.cpuMips();

                        long nextMemory =
                                state.memory[j] + variant.memoryMiB();

                        if (nextCpu > node.totalMips()
                                || nextMemory > node.memoryMiB()) {
                            continue;
                        }

                        feasible = true;

                        State next = new State(state);
                        next.cpu[j] = nextCpu;
                        next.memory[j] = nextMemory;

                        double start = Math.max(
                                state.nodeReady[j],
                                dependencyReady
                        );

                        double finish = start
                                + variant.packageMiB()
                                / node.bandwidthMiBps()
                                + variant.startupSeconds();

                        next.nodeReady[j] = finish;
                        next.ready.put(service.id(), finish);

                        next.assignments.add(new Assignment(
                                service.id(), variant, node
                        ));

                        expanded.add(next);
                    }
                }

                expanded.add(reject(
                        state,
                        service,
                        feasible
                                ? "SEARCH_SKIPPED"
                                : "NO_FEASIBLE_PLACEMENT"
                ));
            }

            expanded.sort(RANK);

            beam = new ArrayList<>(
                    expanded.subList(
                            0,
                            Math.min(beamWidth, expanded.size())
                    )
            );
        }

        State best = beam.get(0);

        return new Result(
                best.assignments,
                best.rejections
        );
    }

    private static List<ServiceSpec> checkedInputOrder(
            List<NodeSpec> nodes, List<ServiceSpec> services
    ) {
        Set<String> nodeIds = new HashSet<>();
        for (NodeSpec node : nodes) {
            if (!nodeIds.add(node.id())) {
                throw new IllegalArgumentException("Duplicate node: " + node.id());
            }
        }
        Set<String> seen = new HashSet<>();
        for (ServiceSpec service : services) {
            if (!seen.containsAll(service.dependencies()) || !seen.add(service.id())) {
                throw new IllegalArgumentException(
                        "Input order must have unique IDs and put dependencies first: "
                                + service.id()
                );
            }
        }
        return List.copyOf(services);
    }

    private static State reject(
            State state,
            ServiceSpec service,
            String reason
    ) {
        State next = new State(state);
        next.rejections.put(service.id(), reason);
        return next;
    }
}
