#[compute]
#version 450

layout(local_size_x = 64) in;

layout(set = 0, binding = 0, std430) buffer Heads {
    int heads[];
};

layout(set = 1, binding = 0, std140) uniform ClearParams {
    uvec4 clear_params;
};

void main() {
    uint id = gl_GlobalInvocationID.x;
    uint table_size = clear_params.x;

    if (id >= table_size) {
        return;
    }

    heads[id] = -1;
}