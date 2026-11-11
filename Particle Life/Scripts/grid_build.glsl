#[compute]
#version 450

layout(local_size_x = 64) in;

// Binding 0: particle positions
layout(set = 0, binding = 0, std430) buffer Positions {
    vec2 positions[];
};

// Binding 1: hash bucket heads
layout(set = 0, binding = 1, std430) buffer Heads {
    int heads[];
};

// Binding 2: linked-list links
layout(set = 0, binding = 2, std430) buffer Next {
    int next[];
};

// Binding 3: actual cell coordinate of each particle
layout(set = 0, binding = 3, std430) buffer CellCoords {
    int cell_coords[];
};

// Set 1, binding 0: grid settings
layout(set = 1, binding = 0, std140) uniform GridParams {
    vec4 grid_params;
};

uint hash_cell(ivec2 cell, uint table_size) {
    uint x = uint(cell.x) * 73856093u;
    uint y = uint(cell.y) * 19349663u;

    return (x ^ y) % table_size;
}

void main() {
    uint id = gl_GlobalInvocationID.x;

    uint particle_count = uint(grid_params.x);
    uint table_size = uint(grid_params.y);
    float cell_size = grid_params.z;

    if (id >= particle_count) {
        return;
    }

    // Find the grid cell containing this particle.
    ivec2 cell = ivec2(floor(positions[id] / cell_size));

    // Store this particle's actual cell coordinates.
    cell_coords[id * 2] = cell.x;
    cell_coords[id * 2 + 1] = cell.y;

    // Convert the cell coordinate into a hash bucket.
    uint bucket = hash_cell(cell, table_size);

    // Insert this particle at the front of the bucket's list.
    next[id] = atomicExchange(heads[bucket], int(id));
}