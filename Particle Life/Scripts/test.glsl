#[compute]
#version 450

layout(local_size_x = 1) in;

layout(set = 0, binding = 0, std430) buffer Positions {
    vec2 positions[];
};

layout(set = 0, binding = 1, std430) buffer Velocities {
    vec2 velocities[];
};

layout(set = 0, binding = 2, std430) buffer Types {
    int types[];
};

layout(set = 0, binding = 3, std430) buffer Rules {
    float rules[];
};

layout(set = 0, binding = 4, std430) buffer Head {
    int head[];
};

layout(set = 0, binding = 5, std430) buffer Next {
    int next[];
};

layout(set = 0, binding = 6, std430) buffer CellCoords {
    int cell_coords[];
};

layout(set = 0, binding = 7, std430) buffer NextPositions {
    vec2 next_positions[];
};

layout(set = 1, binding = 0, std140) uniform Params {
    vec4 params_a;
    vec4 params_b;
};

layout(set = 1, binding = 1, std140) uniform GridParams {
    vec4 grid_params;
};

void main() {
    uint id = gl_GlobalInvocationID.x;

    vec2 center = positions[id];
    int input_type = types[id];

    vec2 force = vec2(0.0);

    float repulsion_distance = params_a.w;
    float attraction_distance = params_a.z;
    float max_speed = params_a.x;

    float interaction_distance = repulsion_distance + attraction_distance;

    float repulsion_squared = repulsion_distance * repulsion_distance;
    float interaction_squared = interaction_distance * interaction_distance;

    float attraction_half = attraction_distance / 2.0;

    int rule_base = input_type * int(params_b.w);

    float cell_size = grid_params.z;
    uint table_size = uint(grid_params.y);

    // Which grid cell contains this particle?
    ivec2 my_cell = ivec2(floor(center / cell_size));

    // How many cells in each direction might contain neighbors?
    int search_radius = int(ceil(interaction_distance / cell_size));

    for (int y = -search_radius; y <= search_radius; y++) {
        for (int x = -search_radius; x <= search_radius; x++) {

            ivec2 wanted_cell = my_cell + ivec2(x, y);

            // Hash the cell to find its linked list.
            uint bucket = uint(
                (uint(wanted_cell.x) * 73856093u)
                ^ (uint(wanted_cell.y) * 19349663u)
            ) % table_size;

            // Walk every particle in this bucket's linked list.
            int i = head[bucket];

            while (i != -1) {

                // Hash collisions can put other cells in this list.
                ivec2 actual_cell = ivec2(
                    cell_coords[i * 2],
                    cell_coords[i * 2 + 1]
                );

                if (all(equal(actual_cell, wanted_cell)) && uint(i) != id) {

                    vec2 diff = positions[i] - center;
                    float distance_squared = dot(diff, diff);

                    if (distance_squared == 0.0) {
                        i = next[i];
                        continue;
                    }

                    if (distance_squared <= interaction_squared) {
                        float distance = sqrt(distance_squared);

                        if (distance <= repulsion_distance) {
                            float force_value =
                                -1.0 + distance / repulsion_distance;

                            force += diff / distance
                                * (max_speed * force_value);
                        }
                        else {
                            float d = distance - repulsion_distance;
                            float t;

                            if (d <= attraction_half) {
                                t = d / attraction_half;
                            }
                            else {
                                t = 1.0 - (d - attraction_half) / attraction_half;
                            }

                            t *= params_b.z;

                            int rule_index = rule_base + types[i];

                            force += diff / distance
                                * (max_speed * t)
                                * rules[rule_index];
                        }
                    }
                }

                // Continue to the next particle in this bucket.
                i = next[i];
            }
        }
    }

    vec2 desired_velocity = force;

    float force_length = length(desired_velocity);

    if (force_length > max_speed) {
        desired_velocity =
            desired_velocity / force_length * max_speed;
    }

    vec2 velocity = velocities[id];

    velocity = mix(
        velocity,
        desired_velocity,
        params_a.y
    );

    float velocity_length = length(velocity);

    if (velocity_length > max_speed) {
        velocity =
            velocity / velocity_length * max_speed;
    }

    next_positions[id] = center + velocity * params_b.x;
    velocities[id] = velocity;
}