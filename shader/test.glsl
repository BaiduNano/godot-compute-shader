#[compute]
#version 450

// Init
layout(local_size_x = 64, local_size_y = 1, local_size_z = 1) in;

// Input Data
layout(set = 0, binding = 0, std430) restrict buffer Ngentot {
    float data[];
} ngentot;

// Input Constants
layout(push_constant) uniform Constants {
    uint total_elements;
} constants;

void main() {
    uint i = gl_GlobalInvocationID.x;
    if (i >= constants.total_elements) {
        return;
    }

    float val = ngentot.data[i];

    val += 1.0;

    ngentot.data[i] = val;
}
