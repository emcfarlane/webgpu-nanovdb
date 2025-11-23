// Port of PNanoVDB C API to WGSL for use in WebGPU shaders.
//
// Original work: Copyright Contributors to the OpenVDB Project
// SPDX-License-Identifier: Apache-2.0
//
// This file is a derivative work based on PNanoVDB.h from the OpenVDB project.
// Ported to WGSL by Edward McFarlane, 2025.
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//     http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.
//
// NOTE: Add a binding for the nanovdb buffer. For example:
//   @group(0) @binding(0) var<storage> nanovdb_buffer: array<u32>;

// --- Buffer ---
struct pnanovdb_buf_t {
    byte_offset: u32, // Index into nanovdb binding storage
    size_in_words: u32, // 4-byte words
}

fn pnanovdb_make_buffer(byte_offset: u32, size_in_words: u32) -> pnanovdb_buf_t {
    var buf: pnanovdb_buf_t;
    buf.byte_offset = byte_offset;
    buf.size_in_words = size_in_words;
    return buf;
}

fn pnanovdb_buf_read_uint32(buf: pnanovdb_buf_t, byte_offset: u32) -> u32 {
    let data = nanovdb_buffer[(buf.byte_offset / 4u) + (byte_offset / 4u)];
    return data;
}
fn pnanovdb_read_uint32(buf: pnanovdb_buf_t, address: pnanovdb_address_t) -> u32 {
    return pnanovdb_buf_read_uint32(buf, address);
}
fn pnanovdb_read_uint64(buf: pnanovdb_buf_t, address: pnanovdb_address_t) -> vec2u {
    return vec2u(
        pnanovdb_buf_read_uint32(buf, address),
        pnanovdb_buf_read_uint32(buf, pnanovdb_address_offset(address, 4u))
    );
}
fn pnanovdb_read_int64(buf: pnanovdb_buf_t, address: pnanovdb_address_t) -> vec2i {
    return vec2i(
        i32(pnanovdb_buf_read_uint32(buf, address)),
        i32(pnanovdb_buf_read_uint32(buf, pnanovdb_address_offset(address, 4u)))
    );
}
fn pnanovdb_uint64_is_equal(a: vec2u, b: vec2u) -> bool {
    return (a.x == b.x) && (a.y == b.y);
}
fn pnanovdb_int64_is_zero(a: vec2i) -> bool {
    return (a.x == 0i) && (a.y == 0i);
}
fn pnanovdb_read_float(buf: pnanovdb_buf_t, address: pnanovdb_address_t) -> f32 {
    return bitcast<f32>(pnanovdb_read_uint32(buf, address));
}
fn pnanovdb_read_coord(buf: pnanovdb_buf_t, address: pnanovdb_address_t) -> vec3i {
    return vec3i(
        i32(pnanovdb_buf_read_uint32(buf, pnanovdb_address_offset(address, 0u))),
        i32(pnanovdb_buf_read_uint32(buf, pnanovdb_address_offset(address, 4u))),
        i32(pnanovdb_buf_read_uint32(buf, pnanovdb_address_offset(address, 8u))),
    );
}

fn pnanovdb_read_mat3x3(buf: pnanovdb_buf_t, address: pnanovdb_address_t) -> mat3x3f {
    return mat3x3f(
        pnanovdb_read_float(buf, pnanovdb_address_offset(address, 0u)),
        pnanovdb_read_float(buf, pnanovdb_address_offset(address, 4u)),
        pnanovdb_read_float(buf, pnanovdb_address_offset(address, 8u)),
        pnanovdb_read_float(buf, pnanovdb_address_offset(address, 12u)),
        pnanovdb_read_float(buf, pnanovdb_address_offset(address, 16u)),
        pnanovdb_read_float(buf, pnanovdb_address_offset(address, 20u)),
        pnanovdb_read_float(buf, pnanovdb_address_offset(address, 24u)),
        pnanovdb_read_float(buf, pnanovdb_address_offset(address, 28u)),
        pnanovdb_read_float(buf, pnanovdb_address_offset(address, 32u)),
    );
}

// pnanovdb
alias pnanovdb_address_t = u32;
//struct pnanovdb_address_t {
//    // NB: Byte offset restricted to 32-bits for WGSL
//    byte_offset: u32,
//}

fn pnanovdb_address_offset(addr: pnanovdb_address_t, offset: u32) -> pnanovdb_address_t {
    return addr + offset;
}

// NOTE: For small scenes, we assume 64-bit offsets fit in 32-bit and ignore high bits
fn pnanovdb_read_int64_as_offset(buf: pnanovdb_buf_t, address: pnanovdb_address_t) -> u32 {
    return pnanovdb_buf_read_uint32(buf, address);
}

// -- PNanoVDB Grid

// -- PNanoVDB Core Data Structure --

const PNANOVDB_MAGIC_NUMBER: vec2u = vec2(0x6f6e614eu, 0x30424456u); // "NanoVDB0" in hex - little endian (uint64_t)
const PNANOVDB_MAGIC_GRID: vec2u = vec2(0x6f6e614eu, 0x31424456u);   // "NanoVDB1" in hex - little endian (uint64_t)
const PNANOVDB_MAGIC_FILE: vec2u = vec2u(0x6f6e614eu, 0x32424456u);  // "NanoVDB2" in hex - little endian (uint64_t)

const PNANOVDB_MAJOR_VERSION_NUMBER: u32 = 32u; // reflects changes to the ABI
const PNANOVDB_MINOR_VERSION_NUMBER: u32 = 8u;  // reflects changes to the API but not ABI
const PNANOVDB_PATCH_VERSION_NUMBER: u32 = 0u;  // reflects bug-fixes with no ABI or API changes

const PNANOVDB_GRID_TYPE_UNKNOWN: u32 = 0u;
const PNANOVDB_GRID_TYPE_FLOAT: u32 = 1u;
const PNANOVDB_GRID_TYPE_DOUBLE: u32 = 2u;
const PNANOVDB_GRID_TYPE_INT16: u32 = 3u;
const PNANOVDB_GRID_TYPE_INT32: u32 = 4u;
const PNANOVDB_GRID_TYPE_INT64: u32 = 5u;
const PNANOVDB_GRID_TYPE_VEC3F: u32 = 6u;
const PNANOVDB_GRID_TYPE_VEC3D: u32 = 7u;
const PNANOVDB_GRID_TYPE_MASK: u32 = 8u;
const PNANOVDB_GRID_TYPE_HALF: u32 = 9u;
const PNANOVDB_GRID_TYPE_UINT32: u32 = 10u;
const PNANOVDB_GRID_TYPE_BOOLEAN: u32 = 11u;
const PNANOVDB_GRID_TYPE_RGBA8: u32 = 12u;
const PNANOVDB_GRID_TYPE_FP4: u32 = 13u;
const PNANOVDB_GRID_TYPE_FP8: u32 = 14u;
const PNANOVDB_GRID_TYPE_FP16: u32 = 15u;
const PNANOVDB_GRID_TYPE_FPN: u32 = 16u;
const PNANOVDB_GRID_TYPE_VEC4F: u32 = 17u;
const PNANOVDB_GRID_TYPE_VEC4D: u32 = 18u;
const PNANOVDB_GRID_TYPE_INDEX: u32 = 19u;
const PNANOVDB_GRID_TYPE_ONINDEX: u32 = 20u;
const PNANOVDB_GRID_TYPE_INDEXMASK: u32 = 21u;
const PNANOVDB_GRID_TYPE_ONINDEXMASK: u32 = 22u;
const PNANOVDB_GRID_TYPE_POINTINDEX: u32 = 23u;
const PNANOVDB_GRID_TYPE_VEC3U8: u32 = 24u;
const PNANOVDB_GRID_TYPE_VEC3U16: u32 = 25u;
const PNANOVDB_GRID_TYPE_UINT8: u32 = 26u;
const PNANOVDB_GRID_TYPE_END: u32 = 27u;

const PNANOVDB_GRID_CLASS_UNKNOWN: u32 = 0u;
const PNANOVDB_GRID_CLASS_LEVEL_SET: u32 = 1u;     // narrow band level set, e.g. SDF
const PNANOVDB_GRID_CLASS_FOG_VOLUME: u32 = 2u;    // fog volume, e.g. density
const PNANOVDB_GRID_CLASS_STAGGERED: u32 = 3u;     // staggered MAC grid, e.g. velocity
const PNANOVDB_GRID_CLASS_POINT_INDEX: u32 = 4u;   // point index grid
const PNANOVDB_GRID_CLASS_POINT_DATA: u32 = 5u;    // point data grid
const PNANOVDB_GRID_CLASS_TOPOLOGY: u32 = 6u;      // grid with active states only (no values)
const PNANOVDB_GRID_CLASS_VOXEL_VOLUME: u32 = 7u;  // volume of geometric cubes, e.g. minecraft
const PNANOVDB_GRID_CLASS_INDEX_GRID: u32 = 8u;    // grid whose values are offsets, e.g. into an external array
const PNANOVDB_GRID_CLASS_TENSOR_GRID: u32 = 9u;   // grid which can have extra metadata and features
const PNANOVDB_GRID_CLASS_END: u32 = 10u;

const PNANOVDB_GRID_FLAGS_HAS_LONG_GRID_NAME: u32 = 1u; // (1 << 0)
const PNANOVDB_GRID_FLAGS_HAS_BBOX: u32 = 2u;           // 1 << 1  
const PNANOVDB_GRID_FLAGS_HAS_MIN_MAX: u32 = 4u;        // 1 << 2
const PNANOVDB_GRID_FLAGS_HAS_AVERAGE: u32 = 8u;        // 1 << 3
const PNANOVDB_GRID_FLAGS_HAS_STD_DEVIATION: u32 = 16u; // 1 << 4
const PNANOVDB_GRID_FLAGS_IS_BREADTH_FIRST: u32 = 32u;  // 1 << 5
const PNANOVDB_GRID_FLAGS_END: u32 = 64u;               // (1 << 6)

const PNANOVDB_LEAF_TYPE_DEFAULT: u32 = 0u;
const PNANOVDB_LEAF_TYPE_LITE: u32 = 1u;
const PNANOVDB_LEAF_TYPE_FP: u32 = 2u;
const PNANOVDB_LEAF_TYPE_INDEX: u32 = 3u;
const PNANOVDB_LEAF_TYPE_INDEXMASK: u32 = 4u;
const PNANOVDB_LEAF_TYPE_POINTINDEX: u32 = 5u;

struct pnanovdb_map_handle_t {
    address: pnanovdb_address_t
};
const PNANOVDB_MAP_SIZE: u32 = 264u;

const PNANOVDB_MAP_OFF_MATF: u32 = 0u;
const PNANOVDB_MAP_OFF_INVMATF: u32 = 36u;
const PNANOVDB_MAP_OFF_VECF: u32 = 72u;
const PNANOVDB_MAP_OFF_TAPERF: u32 = 84u;
const PNANOVDB_MAP_OFF_MATD: u32 = 88u;
const PNANOVDB_MAP_OFF_INVMATD: u32 = 160u;
const PNANOVDB_MAP_OFF_VECD: u32 = 232u;
const PNANOVDB_MAP_OFF_TAPERD: u32 = 256u;

fn pnanovdb_grid_get_map(grid: pnanovdb_grid_handle_t) -> pnanovdb_map_handle_t {
    return pnanovdb_map_handle_t(pnanovdb_address_offset(grid.address, PNANOVDB_GRID_OFF_MAP));
}

fn pnanovdb_map_get_matf(buf: pnanovdb_buf_t, map: pnanovdb_map_handle_t) -> mat3x3f {
    return pnanovdb_read_mat3x3(
        buf, 
        pnanovdb_address_offset(map.address, PNANOVDB_MAP_OFF_MATF)
    );
}
fn pnanovdb_map_get_invmatf(buf: pnanovdb_buf_t, map: pnanovdb_map_handle_t) -> mat3x3f {
    return pnanovdb_read_mat3x3(
        buf, 
        pnanovdb_address_offset(map.address, PNANOVDB_MAP_OFF_INVMATF)
    );
}

struct pnanovdb_grid_handle_t {
    address: pnanovdb_address_t
}
const PNANOVDB_GRID_SIZE: u32 = 672u;

const PNANOVDB_GRID_OFF_MAGIC: u32 = 0u;
const PNANOVDB_GRID_OFF_CHECKSUM: u32 = 8u;
const PNANOVDB_GRID_OFF_VERSION: u32 = 16u;
const PNANOVDB_GRID_OFF_FLAGS: u32 = 20u;
const PNANOVDB_GRID_OFF_GRID_INDEX: u32 = 24u;
const PNANOVDB_GRID_OFF_GRID_COUNT: u32 = 28u;
const PNANOVDB_GRID_OFF_GRID_SIZE: u32 = 32u;
const PNANOVDB_GRID_OFF_GRID_NAME: u32 = 40u;
const PNANOVDB_GRID_OFF_MAP: u32 = 296u;
const PNANOVDB_GRID_OFF_WORLD_BBOX: u32 = 560u;
const PNANOVDB_GRID_OFF_VOXEL_SIZE: u32 = 608u;
const PNANOVDB_GRID_OFF_GRID_CLASS: u32 = 632u;
const PNANOVDB_GRID_OFF_GRID_TYPE: u32 = 636u;
const PNANOVDB_GRID_OFF_BLIND_METADATA_OFFSET: u32 = 640u;
const PNANOVDB_GRID_OFF_BLIND_METADATA_COUNT: u32 = 648u;

struct pnanovdb_gridblindmetadata_handle_t {
    address: pnanovdb_address_t
};
const PNANOVDB_GRIDBLINDMETADATA_SIZE: i32 = 288;

const PNANOVDB_GRIDBLINDMETADATA_OFF_DATA_OFFSET: u32 = 0u;
const PNANOVDB_GRIDBLINDMETADATA_OFF_VALUE_COUNT: u32 = 8u;
const PNANOVDB_GRIDBLINDMETADATA_OFF_VALUE_SIZE: u32 = 16u;
const PNANOVDB_GRIDBLINDMETADATA_OFF_SEMANTIC: u32 = 20u;
const PNANOVDB_GRIDBLINDMETADATA_OFF_DATA_CLASS: u32 = 24u;
const PNANOVDB_GRIDBLINDMETADATA_OFF_DATA_TYPE: u32 = 28u;
const PNANOVDB_GRIDBLINDMETADATA_OFF_NAME: u32 = 32u;


struct pnanovdb_tree_handle_t {
    address: pnanovdb_address_t
};

const PNANOVDB_TREE_SIZE: u32 = 64u;

const PNANOVDB_TREE_OFF_NODE_OFFSET_LEAF: u32 = 0u;
const PNANOVDB_TREE_OFF_NODE_OFFSET_LOWER: u32 = 8u;
const PNANOVDB_TREE_OFF_NODE_OFFSET_UPPER: u32 = 16u;
const PNANOVDB_TREE_OFF_NODE_OFFSET_ROOT: u32 = 24u;
const PNANOVDB_TREE_OFF_NODE_COUNT_LEAF: u32 = 32u;
const PNANOVDB_TREE_OFF_NODE_COUNT_LOWER: u32 = 36u;
const PNANOVDB_TREE_OFF_NODE_COUNT_UPPER: u32 = 40u;
const PNANOVDB_TREE_OFF_TILE_COUNT_LEAF: u32 = 44u;
const PNANOVDB_TREE_OFF_TILE_COUNT_LOWER: u32 = 48u;
const PNANOVDB_TREE_OFF_TILE_COUNT_UPPER: u32 = 52u;
const PNANOVDB_TREE_OFF_VOXEL_COUNT: u32 = 56u;

fn pnanovdb_grid_get_tree(grid: pnanovdb_grid_handle_t) -> pnanovdb_tree_handle_t {
    return pnanovdb_tree_handle_t(pnanovdb_address_offset(grid.address, PNANOVDB_GRID_SIZE));
}

fn pnanovdb_tree_get_node_offset_root(buf: pnanovdb_buf_t, tree: pnanovdb_tree_handle_t) -> u32 {
    // u64 values but must be u32 as values are limited to 32-bit offsets.
    return pnanovdb_buf_read_uint32(buf, pnanovdb_address_offset(tree.address, PNANOVDB_TREE_OFF_NODE_OFFSET_ROOT));
}

struct pnanovdb_root_handle_t {
    address: pnanovdb_address_t
};
const PNANOVDB_ROOT_BASE_SIZE: u32 = 28u;

const PNANOVDB_ROOT_OFF_BBOX_MIN: u32 = 0u;
const PNANOVDB_ROOT_OFF_BBOX_MAX: u32 = 12u;
const PNANOVDB_ROOT_OFF_TABLE_SIZE: u32 = 24u;

fn pnanovdb_tree_get_root(buf: pnanovdb_buf_t, tree: pnanovdb_tree_handle_t) -> pnanovdb_root_handle_t {
    let byte_offset = pnanovdb_tree_get_node_offset_root(buf, tree);
    return pnanovdb_root_handle_t(pnanovdb_address_offset(tree.address, byte_offset));
}
fn pnanovdb_root_get_bbox_min(buf: pnanovdb_buf_t, p: pnanovdb_root_handle_t) -> vec3i {
    return pnanovdb_read_coord(buf, pnanovdb_address_offset(p.address, PNANOVDB_ROOT_OFF_BBOX_MIN));
}
fn pnanovdb_root_get_bbox_max(buf: pnanovdb_buf_t, p: pnanovdb_root_handle_t) -> vec3i {
    return pnanovdb_read_coord(buf, pnanovdb_address_offset(p.address, PNANOVDB_ROOT_OFF_BBOX_MAX));
}

fn pnanovdb_root_get_tile_count(buf: pnanovdb_buf_t, p: pnanovdb_root_handle_t) -> u32 {
    return pnanovdb_read_uint32(buf, pnanovdb_address_offset(p.address, PNANOVDB_ROOT_OFF_TABLE_SIZE));
}

struct pnanovdb_root_tile_handle_t {
    address: pnanovdb_address_t
};
const PNANOVDB_ROOT_TILE_BASE_SIZE: u32 = 20u;

const PNANOVDB_ROOT_TILE_OFF_KEY: u32 = 0u;
const PNANOVDB_ROOT_TILE_OFF_CHILD: u32 = 8u;
const PNANOVDB_ROOT_TILE_OFF_STATE: u32 = 16u;

fn pnanovdb_root_tile_get_key(buf: pnanovdb_buf_t, p: pnanovdb_root_tile_handle_t) -> vec2u {
    return pnanovdb_read_uint64(buf, pnanovdb_address_offset(p.address, PNANOVDB_ROOT_TILE_OFF_KEY));
}

fn pnanovdb_root_tile_get_child(buf: pnanovdb_buf_t, p: pnanovdb_root_tile_handle_t) -> vec2i {
    return pnanovdb_read_int64(buf, pnanovdb_address_offset(p.address, PNANOVDB_ROOT_TILE_OFF_CHILD));
}

fn pnanovdb_root_tile_get_state(buf: pnanovdb_buf_t, p: pnanovdb_root_tile_handle_t) -> u32 {
    return pnanovdb_read_uint32(buf, pnanovdb_address_offset(p.address, PNANOVDB_ROOT_TILE_OFF_STATE));
}

struct pnanovdb_upper_handle_t {
    address: pnanovdb_address_t
};
const PNANOVDB_UPPER_TABLE_COUNT: u32 = 32768u;
const PNANOVDB_UPPER_BASE_SIZE: u32 = 8224u;

const PNANOVDB_UPPER_OFF_BBOX_MIN: u32 = 0u;
const PNANOVDB_UPPER_OFF_BBOX_MAX: u32 = 12u;
const PNANOVDB_UPPER_OFF_FLAGS: u32 = 24u;
const PNANOVDB_UPPER_OFF_VALUE_MASK: u32 = 32u;
const PNANOVDB_UPPER_OFF_CHILD_MASK: u32 = 4128u;

fn pnanovdb_upper_get_bbox_min(buf: pnanovdb_buf_t, p: pnanovdb_upper_handle_t) -> vec3i {
    return pnanovdb_read_coord(buf, pnanovdb_address_offset(p.address, PNANOVDB_UPPER_OFF_BBOX_MIN));
}

fn pnanovdb_upper_get_bbox_max(buf: pnanovdb_buf_t, p: pnanovdb_upper_handle_t) -> vec3i {
    return pnanovdb_read_coord(buf, pnanovdb_address_offset(p.address, PNANOVDB_UPPER_OFF_BBOX_MAX));
}

fn pnanovdb_upper_get_flags(buf: pnanovdb_buf_t, p: pnanovdb_upper_handle_t) -> vec2u {
    return pnanovdb_read_uint64(buf, pnanovdb_address_offset(p.address, PNANOVDB_UPPER_OFF_FLAGS));
}

fn pnanovdb_upper_get_value_mask(buf: pnanovdb_buf_t, p: pnanovdb_upper_handle_t, bit_index: u32) -> bool {
    let value = pnanovdb_read_uint32(buf, pnanovdb_address_offset(p.address, PNANOVDB_UPPER_OFF_VALUE_MASK + 4u * (bit_index >> 5u)));
    return ((value >> (bit_index & 31u)) & 1u) != 0u;
}

fn pnanovdb_upper_get_child_mask(buf: pnanovdb_buf_t, p: pnanovdb_upper_handle_t, bit_index: u32) -> bool {
    let value = pnanovdb_read_uint32(buf, pnanovdb_address_offset(p.address, PNANOVDB_UPPER_OFF_CHILD_MASK + 4u * (bit_index >> 5u)));
    return ((value >> (bit_index & 31u)) & 1u) != 0u;
}

fn pnanovdb_upper_get_min_address(grid_type: u32, buf: pnanovdb_buf_t, node: pnanovdb_upper_handle_t) -> pnanovdb_address_t {
    let byte_offset = pnanovdb_grid_type_constants[grid_type].upper_off_min;
    return pnanovdb_address_offset(node.address, byte_offset);
}

fn pnanovdb_upper_get_max_address(grid_type: u32, buf: pnanovdb_buf_t, node: pnanovdb_upper_handle_t) -> pnanovdb_address_t {
    let byte_offset = pnanovdb_grid_type_constants[grid_type].upper_off_max;
    return pnanovdb_address_offset(node.address, byte_offset);
}

fn pnanovdb_upper_get_ave_address(grid_type: u32, buf: pnanovdb_buf_t, node: pnanovdb_upper_handle_t) -> pnanovdb_address_t {
    let byte_offset = pnanovdb_grid_type_constants[grid_type].upper_off_ave;
    return pnanovdb_address_offset(node.address, byte_offset);
}

fn pnanovdb_upper_get_stddev_address(grid_type: u32, buf: pnanovdb_buf_t, node: pnanovdb_upper_handle_t) -> pnanovdb_address_t {
    let byte_offset = pnanovdb_grid_type_constants[grid_type].upper_off_stddev;
    return pnanovdb_address_offset(node.address, byte_offset);
}

fn pnanovdb_upper_get_table_address(grid_type: u32, buf: pnanovdb_buf_t, node: pnanovdb_upper_handle_t, n: u32) -> pnanovdb_address_t {
    let grid_constants = pnanovdb_grid_type_constants[grid_type];
    let byte_offset = grid_constants.upper_off_table + grid_constants.table_stride * n;
    return pnanovdb_address_offset(node.address, byte_offset);
}

fn pnanovdb_upper_get_table_child(grid_type: u32, buf: pnanovdb_buf_t, node: pnanovdb_upper_handle_t, n: u32) -> u32 {
    let buf_address = pnanovdb_upper_get_table_address(grid_type, buf, node, n);
    // NOTE: For small scenes, we assume 64-bit child offsets fit in 32-bit and ignore high bits
    return pnanovdb_read_int64_as_offset(buf, buf_address);
}

fn pnanovdb_upper_get_child(grid_type: u32, buf: pnanovdb_buf_t, upper: pnanovdb_upper_handle_t, n: u32) -> pnanovdb_lower_handle_t {
    let child_offset = pnanovdb_upper_get_table_child(grid_type, buf, upper, n);
    return pnanovdb_lower_handle_t(pnanovdb_address_offset(upper.address, child_offset));
}

fn pnanovdb_upper_get_value_address_and_level(grid_type: u32, buf: pnanovdb_buf_t, upper: pnanovdb_upper_handle_t, ijk: vec3i) -> pnanovdb_address_and_level_t {
    let n = pnanovdb_upper_coord_to_offset(ijk);
    if pnanovdb_upper_get_child_mask(buf, upper, n) {
        let child = pnanovdb_upper_get_child(grid_type, buf, upper, n);
        return pnanovdb_lower_get_value_address_and_level(grid_type, buf, child, ijk);
    } else {
        let value_address = pnanovdb_upper_get_table_address(grid_type, buf, upper, n);
        return pnanovdb_address_and_level_t(value_address, 2u);
    }
}

struct pnanovdb_lower_handle_t {
    address: pnanovdb_address_t
};
const PNANOVDB_LOWER_TABLE_COUNT: u32 = 4096u;
const PNANOVDB_LOWER_BASE_SIZE: u32 = 1056u;

const PNANOVDB_LOWER_OFF_BBOX_MIN: u32 = 0u;
const PNANOVDB_LOWER_OFF_BBOX_MAX: u32 = 12u;
const PNANOVDB_LOWER_OFF_FLAGS: u32 = 24u;
const PNANOVDB_LOWER_OFF_VALUE_MASK: u32 = 32u;
const PNANOVDB_LOWER_OFF_CHILD_MASK: u32 = 544u;

fn pnanovdb_lower_get_bbox_min(buf: pnanovdb_buf_t, p: pnanovdb_lower_handle_t) -> vec3i {
    return pnanovdb_read_coord(buf, pnanovdb_address_offset(p.address, PNANOVDB_LOWER_OFF_BBOX_MIN));
}

fn pnanovdb_lower_get_bbox_max(buf: pnanovdb_buf_t, p: pnanovdb_lower_handle_t) -> vec3i {
    return pnanovdb_read_coord(buf, pnanovdb_address_offset(p.address, PNANOVDB_LOWER_OFF_BBOX_MAX));
}

fn pnanovdb_lower_get_flags(buf: pnanovdb_buf_t, p: pnanovdb_lower_handle_t) -> vec2u {
    return pnanovdb_read_uint64(buf, pnanovdb_address_offset(p.address, PNANOVDB_LOWER_OFF_FLAGS));
}

fn pnanovdb_lower_get_value_mask(buf: pnanovdb_buf_t, p: pnanovdb_lower_handle_t, bit_index: u32) -> bool {
    let value = pnanovdb_read_uint32(buf, pnanovdb_address_offset(p.address, PNANOVDB_LOWER_OFF_VALUE_MASK + 4u * (bit_index >> 5u)));
    return ((value >> (bit_index & 31u)) & 1u) != 0u;
}

fn pnanovdb_lower_get_child_mask(buf: pnanovdb_buf_t, p: pnanovdb_lower_handle_t, bit_index: u32) -> bool {
    let value = pnanovdb_read_uint32(buf, pnanovdb_address_offset(p.address, PNANOVDB_LOWER_OFF_CHILD_MASK + 4u * (bit_index >> 5u)));
    return ((value >> (bit_index & 31u)) & 1u) != 0u;
}

fn pnanovdb_lower_get_table_address(grid_type: u32, buf: pnanovdb_buf_t, node: pnanovdb_lower_handle_t, n: u32) -> pnanovdb_address_t {
    let grid_constants = pnanovdb_grid_type_constants[grid_type];
    let byte_offset = grid_constants.lower_off_table + grid_constants.table_stride * n;
    return pnanovdb_address_offset(node.address, byte_offset);
}

fn pnanovdb_lower_get_table_child(grid_type: u32, buf: pnanovdb_buf_t, node: pnanovdb_lower_handle_t, n: u32) -> u32 {
    let buf_address = pnanovdb_lower_get_table_address(grid_type, buf, node, n);
    // NOTE: For small scenes, we assume 64-bit child offsets fit in 32-bit and ignore high bits
    return pnanovdb_read_int64_as_offset(buf, buf_address);
}

fn pnanovdb_lower_get_child(grid_type: u32, buf: pnanovdb_buf_t, lower: pnanovdb_lower_handle_t, n: u32) -> pnanovdb_leaf_handle_t {
    let child_offset = pnanovdb_lower_get_table_child(grid_type, buf, lower, n);
    return pnanovdb_leaf_handle_t(pnanovdb_address_offset(lower.address, child_offset));
}

fn pnanovdb_lower_get_value_address_and_level(grid_type: u32, buf: pnanovdb_buf_t, lower: pnanovdb_lower_handle_t, ijk: vec3i) -> pnanovdb_address_and_level_t {
    let n = pnanovdb_lower_coord_to_offset(ijk);
    if pnanovdb_lower_get_child_mask(buf, lower, n) {
        let child = pnanovdb_lower_get_child(grid_type, buf, lower, n);
        let value_address = pnanovdb_leaf_get_table_address(grid_type, buf, child, pnanovdb_leaf_coord_to_offset(ijk));
        return pnanovdb_address_and_level_t(value_address, 0u);
    } else {
        let value_address = pnanovdb_lower_get_table_address(grid_type, buf, lower, n);
        return pnanovdb_address_and_level_t(value_address, 1u);
    }
}

struct pnanovdb_leaf_handle_t {
    address: pnanovdb_address_t
};
const PNANOVDB_LEAF_TABLE_COUNT: u32 = 512u;
const PNANOVDB_LEAF_BASE_SIZE: u32 = 80u;

const PNANOVDB_LEAF_OFF_BBOX_MIN: u32 = 0u;
const PNANOVDB_LEAF_OFF_BBOX_DIF_AND_FLAGS: u32 = 12u;
const PNANOVDB_LEAF_OFF_VALUE_MASK: u32 = 16u;

const PNANOVDB_LEAF_TABLE_NEG_OFF_BBOX_DIF_AND_FLAGS: u32 = 84u;
const PNANOVDB_LEAF_TABLE_NEG_OFF_MINIMUM: u32 = 16u;
const PNANOVDB_LEAF_TABLE_NEG_OFF_QUANTUM: u32 = 12u;

fn pnanovdb_leaf_get_bbox_min(buf: pnanovdb_buf_t, p: pnanovdb_leaf_handle_t) -> vec3i {
    return pnanovdb_read_coord(buf, pnanovdb_address_offset(p.address, PNANOVDB_LEAF_OFF_BBOX_MIN));
}

fn pnanovdb_leaf_get_bbox_dif_and_flags(buf: pnanovdb_buf_t, p: pnanovdb_leaf_handle_t) -> u32 {
    return pnanovdb_read_uint32(buf, pnanovdb_address_offset(p.address, PNANOVDB_LEAF_OFF_BBOX_DIF_AND_FLAGS));
}

fn pnanovdb_leaf_get_value_mask(buf: pnanovdb_buf_t, p: pnanovdb_leaf_handle_t, bit_index: u32) -> bool {
    let value = pnanovdb_read_uint32(buf, pnanovdb_address_offset(p.address, PNANOVDB_LEAF_OFF_VALUE_MASK + 4u * (bit_index >> 5u)));
    return ((value >> (bit_index & 31u)) & 1u) != 0u;
}

fn pnanovdb_leaf_coord_to_offset(ijk: vec3i) -> u32 {
    return (((u32(ijk.x) & 7u) << 6u) + ((u32(ijk.y) & 7u) << 3u) + (u32(ijk.z) & 7u));
}

fn pnanovdb_leaf_get_table_address(grid_type: u32, buf: pnanovdb_buf_t, node: pnanovdb_leaf_handle_t, n: u32) -> pnanovdb_address_t {
    let grid_constants = pnanovdb_grid_type_constants[grid_type];
    let byte_offset = grid_constants.leaf_off_table + ((grid_constants.value_stride_bits * n) >> 3u);
    return pnanovdb_address_offset(node.address, byte_offset);
}

struct pnanovdb_grid_type_constants_t {
    root_off_background: u32,
    root_off_min: u32,
    root_off_max: u32,
    root_off_ave: u32,
    root_off_stddev: u32,
    root_size: u32,
    value_stride_bits: u32,
    table_stride: u32,
    root_tile_off_value: u32,
    root_tile_size: u32,
    upper_off_min: u32,
    upper_off_max: u32,
    upper_off_ave: u32,
    upper_off_stddev: u32,
    upper_off_table: u32,
    upper_size: u32,
    lower_off_min: u32,
    lower_off_max: u32,
    lower_off_ave: u32,
    lower_off_stddev: u32,
    lower_off_table: u32,
    lower_size: u32,
    leaf_off_min: u32,
    leaf_off_max: u32,
    leaf_off_ave: u32,
    leaf_off_stddev: u32,
    leaf_off_table: u32,
    leaf_size: u32,
};

const pnanovdb_grid_type_constants: array<pnanovdb_grid_type_constants_t, 27> = array(
    pnanovdb_grid_type_constants_t(28u, 28u, 28u, 28u, 28u, 32u, 0u, 8u, 20u, 32u, 8224u, 8224u, 8224u, 8224u, 8224u, 270368u, 1056u, 1056u, 1056u, 1056u, 1056u, 33824u, 80u, 80u, 80u, 80u, 96u, 96u),
    pnanovdb_grid_type_constants_t(28u, 32u, 36u, 40u, 44u, 64u, 32u, 8u, 20u, 32u, 8224u, 8228u, 8232u, 8236u, 8256u, 270400u, 1056u, 1060u, 1064u, 1068u, 1088u, 33856u, 80u, 84u, 88u, 92u, 96u, 2144u),
    pnanovdb_grid_type_constants_t(32u, 40u, 48u, 56u, 64u, 96u, 64u, 8u, 24u, 32u, 8224u, 8232u, 8240u, 8248u, 8256u, 270400u, 1056u, 1064u, 1072u, 1080u, 1088u, 33856u, 80u, 88u, 96u, 104u, 128u, 4224u),
    pnanovdb_grid_type_constants_t(28u, 30u, 32u, 36u, 40u, 64u, 16u, 8u, 20u, 32u, 8224u, 8226u, 8228u, 8232u, 8256u, 270400u, 1056u, 1058u, 1060u, 1064u, 1088u, 33856u, 80u, 82u, 84u, 88u, 96u, 1120u),
    pnanovdb_grid_type_constants_t(28u, 32u, 36u, 40u, 44u, 64u, 32u, 8u, 20u, 32u, 8224u, 8228u, 8232u, 8236u, 8256u, 270400u, 1056u, 1060u, 1064u, 1068u, 1088u, 33856u, 80u, 84u, 88u, 92u, 96u, 2144u),
    pnanovdb_grid_type_constants_t(32u, 40u, 48u, 56u, 64u, 96u, 64u, 8u, 24u, 32u, 8224u, 8232u, 8240u, 8248u, 8256u, 270400u, 1056u, 1064u, 1072u, 1080u, 1088u, 33856u, 80u, 88u, 96u, 104u, 128u, 4224u),
    pnanovdb_grid_type_constants_t(28u, 40u, 52u, 64u, 68u, 96u, 96u, 16u, 20u, 32u, 8224u, 8236u, 8248u, 8252u, 8256u, 532544u, 1056u, 1068u, 1080u, 1084u, 1088u, 66624u, 80u, 92u, 104u, 108u, 128u, 6272u),
    pnanovdb_grid_type_constants_t(32u, 56u, 80u, 104u, 112u, 128u, 192u, 24u, 24u, 64u, 8224u, 8248u, 8272u, 8280u, 8288u, 794720u, 1056u, 1080u, 1104u, 1112u, 1120u, 99424u, 80u, 104u, 128u, 136u, 160u, 12448u),
    pnanovdb_grid_type_constants_t(28u, 29u, 30u, 31u, 32u, 64u, 0u, 8u, 20u, 32u, 8224u, 8225u, 8226u, 8227u, 8256u, 270400u, 1056u, 1057u, 1058u, 1059u, 1088u, 33856u, 80u, 80u, 80u, 80u, 96u, 96u),
    pnanovdb_grid_type_constants_t(28u, 30u, 32u, 36u, 40u, 64u, 16u, 8u, 20u, 32u, 8224u, 8226u, 8228u, 8232u, 8256u, 270400u, 1056u, 1058u, 1060u, 1064u, 1088u, 33856u, 80u, 82u, 84u, 88u, 96u, 1120u),
    pnanovdb_grid_type_constants_t(28u, 32u, 36u, 40u, 44u, 64u, 32u, 8u, 20u, 32u, 8224u, 8228u, 8232u, 8236u, 8256u, 270400u, 1056u, 1060u, 1064u, 1068u, 1088u, 33856u, 80u, 84u, 88u, 92u, 96u, 2144u),
    pnanovdb_grid_type_constants_t(28u, 29u, 30u, 31u, 32u, 64u, 1u, 8u, 20u, 32u, 8224u, 8225u, 8226u, 8227u, 8256u, 270400u, 1056u, 1057u, 1058u, 1059u, 1088u, 33856u, 80u, 80u, 80u, 80u, 96u, 160u),
    pnanovdb_grid_type_constants_t(28u, 32u, 36u, 40u, 44u, 64u, 32u, 8u, 20u, 32u, 8224u, 8228u, 8232u, 8236u, 8256u, 270400u, 1056u, 1060u, 1064u, 1068u, 1088u, 33856u, 80u, 84u, 88u, 92u, 96u, 2144u),
    pnanovdb_grid_type_constants_t(28u, 32u, 36u, 40u, 44u, 64u, 0u, 8u, 20u, 32u, 8224u, 8228u, 8232u, 8236u, 8256u, 270400u, 1056u, 1060u, 1064u, 1068u, 1088u, 33856u, 88u, 90u, 92u, 94u, 96u, 352u),
    pnanovdb_grid_type_constants_t(28u, 32u, 36u, 40u, 44u, 64u, 0u, 8u, 20u, 32u, 8224u, 8228u, 8232u, 8236u, 8256u, 270400u, 1056u, 1060u, 1064u, 1068u, 1088u, 33856u, 88u, 90u, 92u, 94u, 96u, 608u),
    pnanovdb_grid_type_constants_t(28u, 32u, 36u, 40u, 44u, 64u, 0u, 8u, 20u, 32u, 8224u, 8228u, 8232u, 8236u, 8256u, 270400u, 1056u, 1060u, 1064u, 1068u, 1088u, 33856u, 88u, 90u, 92u, 94u, 96u, 1120u),
    pnanovdb_grid_type_constants_t(28u, 32u, 36u, 40u, 44u, 64u, 0u, 8u, 20u, 32u, 8224u, 8228u, 8232u, 8236u, 8256u, 270400u, 1056u, 1060u, 1064u, 1068u, 1088u, 33856u, 88u, 90u, 92u, 94u, 96u, 96u),
    pnanovdb_grid_type_constants_t(28u, 44u, 60u, 76u, 80u, 96u, 128u, 16u, 20u, 64u, 8224u, 8240u, 8256u, 8260u, 8288u, 532576u, 1056u, 1072u, 1088u, 1092u, 1120u, 66656u, 80u, 96u, 112u, 116u, 128u, 8320u),
    pnanovdb_grid_type_constants_t(32u, 64u, 96u, 128u, 136u, 160u, 256u, 32u, 24u, 64u, 8224u, 8256u, 8288u, 8296u, 8320u, 1056896u, 1056u, 1088u, 1120u, 1128u, 1152u, 132224u, 80u, 112u, 144u, 152u, 160u, 16544u),
    pnanovdb_grid_type_constants_t(32u, 40u, 48u, 56u, 64u, 96u, 0u, 8u, 24u, 32u, 8224u, 8232u, 8240u, 8248u, 8256u, 270400u, 1056u, 1064u, 1072u, 1080u, 1088u, 33856u, 80u, 80u, 80u, 80u, 80u, 96u),
    pnanovdb_grid_type_constants_t(32u, 40u, 48u, 56u, 64u, 96u, 0u, 8u, 24u, 32u, 8224u, 8232u, 8240u, 8248u, 8256u, 270400u, 1056u, 1064u, 1072u, 1080u, 1088u, 33856u, 80u, 80u, 80u, 80u, 80u, 96u),
    pnanovdb_grid_type_constants_t(32u, 40u, 48u, 56u, 64u, 96u, 0u, 8u, 24u, 32u, 8224u, 8232u, 8240u, 8248u, 8256u, 270400u, 1056u, 1064u, 1072u, 1080u, 1088u, 33856u, 80u, 80u, 80u, 80u, 80u, 160u),
    pnanovdb_grid_type_constants_t(32u, 40u, 48u, 56u, 64u, 96u, 0u, 8u, 24u, 32u, 8224u, 8232u, 8240u, 8248u, 8256u, 270400u, 1056u, 1064u, 1072u, 1080u, 1088u, 33856u, 80u, 80u, 80u, 80u, 80u, 160u),
    pnanovdb_grid_type_constants_t(32u, 40u, 48u, 56u, 64u, 96u, 16u, 8u, 24u, 32u, 8224u, 8232u, 8240u, 8248u, 8256u, 270400u, 1056u, 1064u, 1072u, 1080u, 1088u, 33856u, 80u, 88u, 96u, 96u, 96u, 1120u),
    pnanovdb_grid_type_constants_t(28u, 31u, 34u, 40u, 44u, 64u, 24u, 8u, 20u, 32u, 8224u, 8227u, 8232u, 8236u, 8256u, 270400u, 1056u, 1059u, 1064u, 1068u, 1088u, 33856u, 80u, 83u, 88u, 92u, 96u, 1632u),
    pnanovdb_grid_type_constants_t(28u, 34u, 40u, 48u, 52u, 64u, 48u, 8u, 20u, 32u, 8224u, 8230u, 8236u, 8240u, 8256u, 270400u, 1056u, 1062u, 1068u, 1072u, 1088u, 33856u, 80u, 86u, 92u, 96u, 128u, 3200u),
    pnanovdb_grid_type_constants_t(28u, 29u, 30u, 32u, 36u, 64u, 8u, 8u, 20u, 32u, 8224u, 8225u, 8228u, 8232u, 8256u, 270400u, 1056u, 1057u, 1060u, 1064u, 1088u, 33856u, 80u, 81u, 84u, 88u, 96u, 608u),
);

// --- Basic Lookup ---

fn pnanovdb_root_get_tile_zero(grid_type: u32, root: pnanovdb_root_handle_t) -> pnanovdb_root_tile_handle_t {
    // Root tiles start immediately after the root header
    return pnanovdb_root_tile_handle_t(pnanovdb_address_offset(root.address, pnanovdb_grid_type_constants[grid_type].root_size));
}

fn pnanovdb_root_get_child(grid_type: u32, buf: pnanovdb_buf_t, root: pnanovdb_root_handle_t, tile: pnanovdb_root_tile_handle_t) -> pnanovdb_upper_handle_t {
    var upper = pnanovdb_upper_handle_t(root.address);
    let child_offset = pnanovdb_root_tile_get_child(buf, tile);
    // NOTE: For small scenes, we assume 64-bit offsets fit in 32-bit and ignore high bits
    upper.address = pnanovdb_address_offset(upper.address, u32(child_offset.x));
    return upper;
}

fn pnanovdb_coord_to_key(ijk: vec3i) -> vec2u {
    // Use the non-native 64-bit path since WGSL doesn't have native 64-bit
    let iu = u32(ijk.x) >> 12u;
    let ju = u32(ijk.y) >> 12u;
    let ku = u32(ijk.z) >> 12u;
    let key_x = ku | (ju << 21u);
    let key_y = (iu << 10u) | (ju >> 11u);
    return vec2u(key_x, key_y);
}

fn pnanovdb_root_find_tile(grid_type: u32, buf: pnanovdb_buf_t, root: pnanovdb_root_handle_t, ijk: vec3i) -> pnanovdb_root_tile_handle_t {
    let tile_count = pnanovdb_root_get_tile_count(buf, root);
    var tile = pnanovdb_root_get_tile_zero(grid_type, root);
    let key = pnanovdb_coord_to_key(ijk);

    for (var i = 0u; i < tile_count; i++) {
        if pnanovdb_uint64_is_equal(key, pnanovdb_root_tile_get_key(buf, tile)) {
            return tile;
        }
        tile.address = pnanovdb_address_offset(tile.address, pnanovdb_grid_type_constants[grid_type].root_tile_size);
    }
    // Return null tile if not found
    return pnanovdb_root_tile_handle_t(0u);
}

// --- Lower Node ---

fn pnanovdb_lower_coord_to_offset(ijk: vec3i) -> u32 {
    return (((u32(ijk.x) & 127u) >> 3u) << (8u)) + (((u32(ijk.y) & 127u) >> 3u) << (4u)) + ((u32(ijk.z) & 127u) >> 3u);
}


// --- Upper Node ---

fn pnanovdb_upper_coord_to_offset(ijk: vec3i) -> u32 {
    return (((u32(ijk.x) & 4095u) >> 7u) << 10u) + (((u32(ijk.y) & 4095u) >> 7u) << 5u) + ((u32(ijk.z) & 4095u) >> 7u);
}


// --- ReadAccessor ---

struct pnanovdb_readaccessor_t {
    key: vec3i,
    leaf: pnanovdb_leaf_handle_t,
    lower: pnanovdb_lower_handle_t,
    upper: pnanovdb_upper_handle_t,
    root: pnanovdb_root_handle_t,
};

fn pnanovdb_readaccessor_init(acc: ptr<function, pnanovdb_readaccessor_t>, root: pnanovdb_root_handle_t) {
    (*acc).key.x = 0x7FFFFFFF;
    (*acc).key.y = 0x7FFFFFFF;
    (*acc).key.z = 0x7FFFFFFF;
    (*acc).upper.address = 0u;
    (*acc).lower.address = 0u;
    (*acc).leaf.address = 0u;
    (*acc).root = root;
}

fn pnanovdb_readaccessor_iscached0(acc: ptr<function, pnanovdb_readaccessor_t>, dirty: i32) -> bool {
    if (*acc).leaf.address == 0u {
        return false;
    }
    if (dirty & ~i32((1u << 3u) - 1u)) != 0 {
        (*acc).leaf.address = 0u;
        return false;
    }
    return true;
}

fn pnanovdb_readaccessor_iscached1(acc: ptr<function, pnanovdb_readaccessor_t>, dirty: i32) -> bool {
    if (*acc).lower.address == 0u {
        return false;
    }
    if (dirty & ~i32((1u << 7u) - 1u)) != 0 {
        (*acc).lower.address = 0u;
        return false;
    }
    return true;
}

fn pnanovdb_readaccessor_iscached2(acc: ptr<function, pnanovdb_readaccessor_t>, dirty: i32) -> bool {
    if (*acc).upper.address == 0u {
        return false;
    }
    if (dirty & ~i32((1u << 12u) - 1u)) != 0 {
        (*acc).upper.address = 0u;
        return false;
    }
    return true;
}

fn pnanovdb_readaccessor_computedirty(acc: ptr<function, pnanovdb_readaccessor_t>, ijk: vec3i) -> i32 {
    return ((ijk.x ^ (*acc).key.x) | (ijk.y ^ (*acc).key.y) | (ijk.z ^ (*acc).key.z));
}

fn pnanovdb_leaf_get_value_address_and_cache(grid_type: u32, buf: pnanovdb_buf_t, leaf: pnanovdb_leaf_handle_t, ijk: vec3i, acc: ptr<function, pnanovdb_readaccessor_t>) -> pnanovdb_address_t {
    let n = pnanovdb_leaf_coord_to_offset(ijk);
    return pnanovdb_leaf_get_table_address(grid_type, buf, leaf, n);
}

struct pnanovdb_address_and_level_t {
    address: pnanovdb_address_t,
    level: u32,
}


fn pnanovdb_lower_get_value_address_and_level_and_cache(
    grid_type: u32,
    buf: pnanovdb_buf_t,
    lower: pnanovdb_lower_handle_t,
    ijk: vec3i,
    acc: ptr<function, pnanovdb_readaccessor_t>,
) -> pnanovdb_address_and_level_t {
    let n = pnanovdb_lower_coord_to_offset(ijk);
    var value_address: pnanovdb_address_t;
    var level: u32;

    if pnanovdb_lower_get_child_mask(buf, lower, n) {
        let child = pnanovdb_lower_get_child(grid_type, buf, lower, n);
        (*acc).leaf = child;
        (*acc).key = ijk;
        value_address = pnanovdb_leaf_get_value_address_and_cache(grid_type, buf, child, ijk, acc);
        level = 0u;
    } else {
        value_address = pnanovdb_lower_get_table_address(grid_type, buf, lower, n);
        level = 1u;
    }
    return pnanovdb_address_and_level_t(value_address, level);
}

fn pnanovdb_upper_get_value_address_and_level_and_cache(
    grid_type: u32,
    buf: pnanovdb_buf_t,
    upper: pnanovdb_upper_handle_t,
    ijk: vec3i,
    acc: ptr<function, pnanovdb_readaccessor_t>,
) -> pnanovdb_address_and_level_t {
    let n = pnanovdb_upper_coord_to_offset(ijk);
    if pnanovdb_upper_get_child_mask(buf, upper, n) {
        let child = pnanovdb_upper_get_child(grid_type, buf, upper, n);
        (*acc).lower = child;
        (*acc).key = ijk;
        return pnanovdb_lower_get_value_address_and_level_and_cache(grid_type, buf, child, ijk, acc);
    }
    let value_address = pnanovdb_upper_get_table_address(grid_type, buf, upper, n);
    return pnanovdb_address_and_level_t(value_address, 2u);
}

fn pnanovdb_root_get_value_address_and_level_and_cache(
    grid_type: u32,
    buf: pnanovdb_buf_t,
    root: pnanovdb_root_handle_t,
    ijk: vec3i,
    acc: ptr<function, pnanovdb_readaccessor_t>,
) -> pnanovdb_address_and_level_t {
    let tile = pnanovdb_root_find_tile(grid_type, buf, root, ijk);
    var ret: pnanovdb_address_t;
    var level: u32;

    if tile.address == 0u {
        ret = pnanovdb_address_offset(root.address, pnanovdb_grid_type_constants[grid_type].root_off_background);
        level = 4u;
    } else if pnanovdb_int64_is_zero(pnanovdb_root_tile_get_child(buf, tile)) {
        ret = pnanovdb_address_offset(tile.address, pnanovdb_grid_type_constants[grid_type].root_tile_off_value);
        level = 3u;
    } else {
        let child = pnanovdb_root_get_child(grid_type, buf, root, tile);
        (*acc).upper = child;
        (*acc).key = ijk;
        return pnanovdb_upper_get_value_address_and_level_and_cache(grid_type, buf, child, ijk, acc);
    }
    return pnanovdb_address_and_level_t(ret, level);
}

fn pnanovdb_readaccessor_get_value_address_and_level(grid_type: u32, buf: pnanovdb_buf_t, acc: ptr<function, pnanovdb_readaccessor_t>, ijk: vec3i) -> pnanovdb_address_and_level_t {
    let dirty = pnanovdb_readaccessor_computedirty(acc, ijk);

    var result: pnanovdb_address_and_level_t;
    if pnanovdb_readaccessor_iscached0(acc, dirty) {
        result.address = pnanovdb_leaf_get_value_address_and_cache(grid_type, buf, (*acc).leaf, ijk, acc);
        result.level = 0u;
    } else if pnanovdb_readaccessor_iscached1(acc, dirty) {
        let temp = pnanovdb_lower_get_value_address_and_level_and_cache(grid_type, buf, (*acc).lower, ijk, acc);
        result.address = temp.address;
        result.level = temp.level;
    } else if pnanovdb_readaccessor_iscached2(acc, dirty) {
        let temp = pnanovdb_upper_get_value_address_and_level_and_cache(grid_type, buf, (*acc).upper, ijk, acc);
        result.address = temp.address;
        result.level = temp.level;
    } else {
        let temp = pnanovdb_root_get_value_address_and_level_and_cache(grid_type, buf, (*acc).root, ijk, acc);
        result.address = temp.address;
        result.level = temp.level;
    }
    return result;
}

fn pnanovdb_readaccessor_get_value_address(grid_type: u32, buf: pnanovdb_buf_t, acc: ptr<function, pnanovdb_readaccessor_t>, ijk: vec3i) -> pnanovdb_address_t {
    return pnanovdb_readaccessor_get_value_address_and_level(grid_type, buf, acc, ijk).address;
}

// --- ReadAccessor GetDim ---

// pnanovdb_leaf_get_dim_and_cache returns 1 (leaf level dimension)
fn pnanovdb_leaf_get_dim_and_cache(grid_type: u32, buf: pnanovdb_buf_t, leaf: pnanovdb_leaf_handle_t, ijk: vec3i, acc: ptr<function, pnanovdb_readaccessor_t>) -> u32 {
    return 1u;
}

// pnanovdb_lower_get_dim_and_cache returns 8 (1<<3) for lower nodes, or recurses to leaf
fn pnanovdb_lower_get_dim_and_cache(grid_type: u32, buf: pnanovdb_buf_t, lower: pnanovdb_lower_handle_t, ijk: vec3i, acc: ptr<function, pnanovdb_readaccessor_t>) -> u32 {
    let n = pnanovdb_lower_coord_to_offset(ijk);
    var ret: u32;
    if pnanovdb_lower_get_child_mask(buf, lower, n) {
        let child = pnanovdb_lower_get_child(grid_type, buf, lower, n);
        (*acc).leaf = child;
        (*acc).key = ijk;
        ret = pnanovdb_leaf_get_dim_and_cache(grid_type, buf, child, ijk, acc);
    } else {
        ret = (1u << 3u); // node 0 dim
    }
    return ret;
}

// pnanovdb_upper_get_dim_and_cache returns 128 (1<<7) for upper nodes, or recurses to lower
fn pnanovdb_upper_get_dim_and_cache(grid_type: u32, buf: pnanovdb_buf_t, upper: pnanovdb_upper_handle_t, ijk: vec3i, acc: ptr<function, pnanovdb_readaccessor_t>) -> u32 {
    let n = pnanovdb_upper_coord_to_offset(ijk);
    var ret: u32;
    if pnanovdb_upper_get_child_mask(buf, upper, n) {
        let child = pnanovdb_upper_get_child(grid_type, buf, upper, n);
        (*acc).lower = child;
        (*acc).key = ijk;
        ret = pnanovdb_lower_get_dim_and_cache(grid_type, buf, child, ijk, acc);
    } else {
        ret = (1u << (4u + 3u)); // node 1 dim
    }
    return ret;
}

// pnanovdb_root_get_dim_and_cache returns 4096 (1<<12) for root nodes, or recurses to upper
fn pnanovdb_root_get_dim_and_cache(grid_type: u32, buf: pnanovdb_buf_t, root: pnanovdb_root_handle_t, ijk: vec3i, acc: ptr<function, pnanovdb_readaccessor_t>) -> u32 {
    let tile = pnanovdb_root_find_tile(grid_type, buf, root, ijk);
    var ret: u32;
    if tile.address == 0u {
        ret = 1u << (5u + 4u + 3u); // background, node 2 dim
    } else if pnanovdb_int64_is_zero(pnanovdb_root_tile_get_child(buf, tile)) {
        ret = 1u << (5u + 4u + 3u); // tile value, node 2 dim
    } else {
        let child = pnanovdb_root_get_child(grid_type, buf, root, tile);
        (*acc).upper = child;
        (*acc).key = ijk;
        ret = pnanovdb_upper_get_dim_and_cache(grid_type, buf, child, ijk, acc);
    }
    return ret;
}

// pnanovdb_readaccessor_get_dim is the main entry point using cached hierarchy traversal.
fn pnanovdb_readaccessor_get_dim(grid_type: u32, buf: pnanovdb_buf_t, acc: ptr<function, pnanovdb_readaccessor_t>, ijk: vec3i) -> u32 {
    let dirty = pnanovdb_readaccessor_computedirty(acc, ijk);

    var dim: u32;
    if pnanovdb_readaccessor_iscached0(acc, dirty) {
        dim = pnanovdb_leaf_get_dim_and_cache(grid_type, buf, (*acc).leaf, ijk, acc);
    } else if pnanovdb_readaccessor_iscached1(acc, dirty) {
        dim = pnanovdb_lower_get_dim_and_cache(grid_type, buf, (*acc).lower, ijk, acc);
    } else if pnanovdb_readaccessor_iscached2(acc, dirty) {
        dim = pnanovdb_upper_get_dim_and_cache(grid_type, buf, (*acc).upper, ijk, acc);
    } else {
        dim = pnanovdb_root_get_dim_and_cache(grid_type, buf, (*acc).root, ijk, acc);
    }
    return dim;
}

// --- ReadAccessor IsActive ---

// pnanovdb_leaf_is_active_and_cache checks if a voxel is active using the leaf's value mask.
fn pnanovdb_leaf_is_active_and_cache(grid_type: u32, buf: pnanovdb_buf_t, leaf: pnanovdb_leaf_handle_t, ijk: vec3i, acc: ptr<function, pnanovdb_readaccessor_t>) -> bool {
    let n = pnanovdb_leaf_coord_to_offset(ijk);
    return pnanovdb_leaf_get_value_mask(buf, leaf, n);
}

// pnanovdb_lower_is_active_and_cache checks child mask, recurses to leaf or checks lower value mask.
fn pnanovdb_lower_is_active_and_cache(grid_type: u32, buf: pnanovdb_buf_t, lower: pnanovdb_lower_handle_t, ijk: vec3i, acc: ptr<function, pnanovdb_readaccessor_t>) -> bool {
    let n = pnanovdb_lower_coord_to_offset(ijk);
    var is_active: bool;
    if pnanovdb_lower_get_child_mask(buf, lower, n) {
        let child = pnanovdb_lower_get_child(grid_type, buf, lower, n);
        (*acc).leaf = child;
        (*acc).key = ijk;
        is_active = pnanovdb_leaf_is_active_and_cache(grid_type, buf, child, ijk, acc);
    } else {
        is_active = pnanovdb_lower_get_value_mask(buf, lower, n);
    }
    return is_active;
}

// pnanovdb_upper_is_active_and_cache checks child mask, recurses to lower or checks upper value mask.
fn pnanovdb_upper_is_active_and_cache(grid_type: u32, buf: pnanovdb_buf_t, upper: pnanovdb_upper_handle_t, ijk: vec3i, acc: ptr<function, pnanovdb_readaccessor_t>) -> bool {
    let n = pnanovdb_upper_coord_to_offset(ijk);
    var is_active: bool;
    if pnanovdb_upper_get_child_mask(buf, upper, n) {
        let child = pnanovdb_upper_get_child(grid_type, buf, upper, n);
        (*acc).lower = child;
        (*acc).key = ijk;
        is_active = pnanovdb_lower_is_active_and_cache(grid_type, buf, child, ijk, acc);
    } else {
        is_active = pnanovdb_upper_get_value_mask(buf, upper, n);
    }
    return is_active;
}

// pnanovdb_root_is_active_and_cache finds tile, checks background/tile state, or recurses to upper.
fn pnanovdb_root_is_active_and_cache(grid_type: u32, buf: pnanovdb_buf_t, root: pnanovdb_root_handle_t, ijk: vec3i, acc: ptr<function, pnanovdb_readaccessor_t>) -> bool {
    let tile = pnanovdb_root_find_tile(grid_type, buf, root, ijk);
    var is_active: bool;
    if tile.address == 0u {
        is_active = false; // background
    } else {
        let child_offset = pnanovdb_root_tile_get_child(buf, tile);
        if child_offset.x == 0i && child_offset.y == 0i {
            let state = pnanovdb_root_tile_get_state(buf, tile);
            is_active = state != 0u; // tile value
        } else {
            let child = pnanovdb_root_get_child(grid_type, buf, root, tile);
            (*acc).upper = child;
            (*acc).key = ijk;
            is_active = pnanovdb_upper_is_active_and_cache(grid_type, buf, child, ijk, acc);
        }
    }
    return is_active;
}

// pnanovdb_readaccessor_is_active is the main entry point using cached hierarchy traversal.
fn pnanovdb_readaccessor_is_active(grid_type: u32, buf: pnanovdb_buf_t, acc: ptr<function, pnanovdb_readaccessor_t>, ijk: vec3i) -> bool {
    let dirty = pnanovdb_readaccessor_computedirty(acc, ijk);

    var is_active: bool;
    if pnanovdb_readaccessor_iscached0(acc, dirty) {
        is_active = pnanovdb_leaf_is_active_and_cache(grid_type, buf, (*acc).leaf, ijk, acc);
    } else if pnanovdb_readaccessor_iscached1(acc, dirty) {
        is_active = pnanovdb_lower_is_active_and_cache(grid_type, buf, (*acc).lower, ijk, acc);
    } else if pnanovdb_readaccessor_iscached2(acc, dirty) {
        is_active = pnanovdb_upper_is_active_and_cache(grid_type, buf, (*acc).upper, ijk, acc);
    } else {
        is_active = pnanovdb_root_is_active_and_cache(grid_type, buf, (*acc).root, ijk, acc);
    }
    return is_active;
}

// --- HDDA ---
const PNANOVDB_HDDA_FLOAT_MAX: f32 = 1e38f;

struct pnanovdb_hdda_t {
    dim: i32,
    tmin: f32,
    tmax: f32,
    voxel: vec3i,
    step: vec3i,
    delta: vec3f,
    next: vec3f,
};

fn pnanovdb_hdda_pos_to_ijk(pos: vec3f) -> vec3i {
    return vec3i(floor(pos));
}
fn pnanovdb_hdda_pos_to_voxel(pos: vec3f, dim: i32) -> vec3i {
    let mask = ~(dim - 1);
    return vec3i(floor(pos)) & vec3i(mask, mask, mask);
}
fn pnanovdb_hdda_ray_start(origin: vec3f, tmin: f32, direction: vec3f) -> vec3f {
    return origin + direction * tmin;
}

//   The HDDA (Hierarchical Digital Differential Analyzer) init function sets up efficient 3D grid traversal by:
//  - Computing the starting voxel position
//  - Calculating step directions and delta values for each axis
//  - Setting up the "next" boundaries for efficient stepping through the grid
//
//  This is essential for NanoVDB raymarching as it provides fast, hierarchical traversal through the sparse voxel structure.
fn pnanovdb_hdda_init(hdda: ptr<function, pnanovdb_hdda_t>, origin: vec3f, tmin: f32, direction: vec3f, tmax: f32, dim: i32) {
    (*hdda).dim = dim;
    (*hdda).tmin = tmin;
    (*hdda).tmax = tmax;

    let pos = pnanovdb_hdda_ray_start(origin, tmin, direction);
    let dir_inv = 1.0 / direction;

    (*hdda).voxel = pnanovdb_hdda_pos_to_voxel(pos, dim);

    // x
    if direction.x == 0.0 {
        (*hdda).next.x = PNANOVDB_HDDA_FLOAT_MAX;
        (*hdda).step.x = 0;
        (*hdda).delta.x = 0.0;
    } else if dir_inv.x > 0.0 {
        (*hdda).step.x = 1;
        (*hdda).next.x = (*hdda).tmin + (f32((*hdda).voxel.x) + f32(dim) - pos.x) * dir_inv.x;
        (*hdda).delta.x = dir_inv.x;
    } else {
        (*hdda).step.x = -1;
        (*hdda).next.x = (*hdda).tmin + (f32((*hdda).voxel.x) - pos.x) * dir_inv.x;
        (*hdda).delta.x = -dir_inv.x;
    }

    // y
    if direction.y == 0.0 {
        (*hdda).next.y = PNANOVDB_HDDA_FLOAT_MAX;
        (*hdda).step.y = 0;
        (*hdda).delta.y = 0.0;
    } else if dir_inv.y > 0.0 {
        (*hdda).step.y = 1;
        (*hdda).next.y = (*hdda).tmin + (f32((*hdda).voxel.y) + f32(dim) - pos.y) * dir_inv.y;
        (*hdda).delta.y = dir_inv.y;
    } else {
        (*hdda).step.y = -1;
        (*hdda).next.y = (*hdda).tmin + (f32((*hdda).voxel.y) - pos.y) * dir_inv.y;
        (*hdda).delta.y = -dir_inv.y;
    }

    // z
    if direction.z == 0.0 {
        (*hdda).next.z = PNANOVDB_HDDA_FLOAT_MAX;
        (*hdda).step.z = 0;
        (*hdda).delta.z = 0.0;
    } else if dir_inv.z > 0.0 {
        (*hdda).step.z = 1;
        (*hdda).next.z = (*hdda).tmin + (f32((*hdda).voxel.z) + f32(dim) - pos.z) * dir_inv.z;
        (*hdda).delta.z = dir_inv.z;
    } else {
        (*hdda).step.z = -1;
        (*hdda).next.z = (*hdda).tmin + (f32((*hdda).voxel.z) - pos.z) * dir_inv.z;
        (*hdda).delta.z = -dir_inv.z;
    }
}

// The pnanovdb_hdda_update function is used to switch the HDDA traversal to a different hierarchical level (different dim value) during raymarching:
//
//  - Early Exit: If already at the requested dimension, no work needed
//  - Recalculate Position: Updates the current voxel position for the new dimension
//  - Update Boundaries: Recalculates the next boundary crossings for each axis
//  - Dimension Adjustment: Accounts for positive vs negative step directions
//
//  This is crucial for NanoVDB's hierarchical traversal, allowing the ray to efficiently switch between different levels of detail (leaf nodes, internal nodes, etc.) as it moves
//  through the sparse voxel structure.
fn pnanovdb_hdda_update(hdda: ptr<function, pnanovdb_hdda_t>, origin: vec3f, direction: vec3f, dim: i32) -> bool {
    if (*hdda).dim == dim {
        return false;
    }
    (*hdda).dim = dim;

    let pos = pnanovdb_hdda_ray_start(origin, (*hdda).tmin, direction);
    let dir_inv = 1.0 / direction;

    (*hdda).voxel = pnanovdb_hdda_pos_to_voxel(pos, dim);

    if (*hdda).step.x != 0 {
        (*hdda).next.x = (*hdda).tmin + (f32((*hdda).voxel.x) - pos.x) * dir_inv.x;
        if (*hdda).step.x > 0 {
            (*hdda).next.x += f32(dim) * dir_inv.x;
        }
    }
    if (*hdda).step.y != 0 {
        (*hdda).next.y = (*hdda).tmin + (f32((*hdda).voxel.y) - pos.y) * dir_inv.y;
        if (*hdda).step.y > 0 {
            (*hdda).next.y += f32(dim) * dir_inv.y;
        }
    }
    if (*hdda).step.z != 0 {
        (*hdda).next.z = (*hdda).tmin + (f32((*hdda).voxel.z) - pos.z) * dir_inv.z;
        if (*hdda).step.z > 0 {
            (*hdda).next.z += f32(dim) * dir_inv.z;
        }
    }

    return true;
}

fn pnanovdb_hdda_step(hdda: ptr<function, pnanovdb_hdda_t>) -> bool {
    var ret: bool;
    if (*hdda).next.x < (*hdda).next.y && (*hdda).next.x < (*hdda).next.z {
        // PNANOVDB_ENFORCE_FORWARD_STEPPING
        if (*hdda).next.x <= (*hdda).tmin {
            (*hdda).next.x += (*hdda).tmin - 0.999999 * (*hdda).next.x + 1.0e-6;
        }
        (*hdda).tmin = (*hdda).next.x;
        (*hdda).next.x += f32((*hdda).dim) * (*hdda).delta.x;
        (*hdda).voxel.x += (*hdda).dim * (*hdda).step.x;
        ret = (*hdda).tmin <= (*hdda).tmax;
    } else if (*hdda).next.y < (*hdda).next.z {
        // PNANOVDB_ENFORCE_FORWARD_STEPPING
        if (*hdda).next.y <= (*hdda).tmin {
            (*hdda).next.y += (*hdda).tmin - 0.999999 * (*hdda).next.y + 1.0e-6;
        }
        (*hdda).tmin = (*hdda).next.y;
        (*hdda).next.y += f32((*hdda).dim) * (*hdda).delta.y;
        (*hdda).voxel.y += (*hdda).dim * (*hdda).step.y;
        ret = (*hdda).tmin <= (*hdda).tmax;
    } else {
        // PNANOVDB_ENFORCE_FORWARD_STEPPING
        if (*hdda).next.z <= (*hdda).tmin {
            (*hdda).next.z += (*hdda).tmin - 0.999999 * (*hdda).next.z + 1.0e-6;
        }
        (*hdda).tmin = (*hdda).next.z;
        (*hdda).next.z += f32((*hdda).dim) * (*hdda).delta.z;
        (*hdda).voxel.z += (*hdda).dim * (*hdda).step.z;
        ret = (*hdda).tmin <= (*hdda).tmax;
    }
    return ret;
}

fn pnanovdb_hdda_ray_clip(
    bbox_min: vec3f,
    bbox_max: vec3f,
    origin: vec3f,
    tmin: ptr<function, f32>,
    direction: vec3f,
    tmax: ptr<function, f32>
) -> bool {
    let dir_inv = 1.0 / direction;
    let t0 = (bbox_min - origin) * dir_inv;
    let t1 = (bbox_max - origin) * dir_inv;
    let tmin3 = min(t0, t1);
    let tmax3 = max(t0, t1);
    let tnear = max(tmin3.x, max(tmin3.y, tmin3.z));
    let tfar = min(tmax3.x, min(tmax3.y, tmax3.z));
    let hit = tnear <= tfar;
    *tmin = max(*tmin, tnear);
    *tmax = min(*tmax, tfar);
    return hit;
}

// pnanovdb_hdda_zero_crossing function implements zero-crossing detection for level set raymarching.
fn pnanovdb_hdda_zero_crossing(
    grid_type: u32,
    buf: pnanovdb_buf_t,
    acc: ptr<function, pnanovdb_readaccessor_t>,
    origin: vec3f,
    tmin: f32,
    direction: vec3f,
    tmax: f32,
    thit: ptr<function, f32>,
    v: ptr<function, f32>
) -> bool {
    let bbox_min = pnanovdb_root_get_bbox_min(buf, (*acc).root);
    let bbox_max = pnanovdb_root_get_bbox_max(buf, (*acc).root);
    let bbox_minf = vec3f(bbox_min);
    let bbox_maxf = vec3f(bbox_max + vec3i(1, 1, 1));

    var tmin_mut = tmin;
    var tmax_mut = tmax;
    let hit = pnanovdb_hdda_ray_clip(bbox_minf, bbox_maxf, origin, &tmin_mut, direction, &tmax_mut);
    if !hit || tmax_mut > 1.0e20 {
        return false;
    }

    let pos = pnanovdb_hdda_ray_start(origin, tmin_mut, direction);
    var ijk = pnanovdb_hdda_pos_to_ijk(pos);

    let address = pnanovdb_readaccessor_get_value_address(PNANOVDB_GRID_TYPE_FLOAT, buf, acc, ijk);
    let v0 = pnanovdb_read_float(buf, address);
    let dim = i32(pnanovdb_readaccessor_get_dim(PNANOVDB_GRID_TYPE_FLOAT, buf, acc, ijk));
    var hdda: pnanovdb_hdda_t;
    pnanovdb_hdda_init(&hdda, origin, tmin_mut, direction, tmax_mut, dim);

    var outer_loop_count = 0;
    while pnanovdb_hdda_step(&hdda) && outer_loop_count < 1000 {
        outer_loop_count++;
        let pos_start = pnanovdb_hdda_ray_start(origin, hdda.tmin + 1.0001, direction);
        ijk = pnanovdb_hdda_pos_to_ijk(pos_start);
        let new_dim = i32(pnanovdb_readaccessor_get_dim(PNANOVDB_GRID_TYPE_FLOAT, buf, acc, ijk));
        let updated = pnanovdb_hdda_update(&hdda, origin, direction, new_dim);
        if hdda.dim > 1 || !pnanovdb_readaccessor_is_active(grid_type, buf, acc, ijk) {
            continue;
        }
        var inner_loop_count = 0;
        while pnanovdb_hdda_step(&hdda) && pnanovdb_readaccessor_is_active(grid_type, buf, acc, hdda.voxel) && inner_loop_count < 100 {
            inner_loop_count++;
            ijk = hdda.voxel;
            let value_address = pnanovdb_readaccessor_get_value_address(PNANOVDB_GRID_TYPE_FLOAT, buf, acc, ijk);
            *v = pnanovdb_read_float(buf, value_address);
            if (*v) * v0 < 0.0 {
                *thit = hdda.tmin;
                return true;
            }
        }
    }
    return false;
}

// Sample 2x2x2 stencil of voxel values around a point
// Returns array indexed as [x][y][z] where x,y,z are in {0,1}
fn pnanovdb_sample_stencil(
    buf: pnanovdb_buf_t,
    acc: ptr<function, pnanovdb_readaccessor_t>,
    ijk: vec3i
) -> array<array<array<f32, 2>, 2>, 2> {
    var v: array<array<array<f32, 2>, 2>, 2>;

    for (var x = 0; x < 2; x++) {
        for (var y = 0; y < 2; y++) {
            for (var z = 0; z < 2; z++) {
                let offset = vec3i(x, y, z);
                let addr = pnanovdb_readaccessor_get_value_address(
                    PNANOVDB_GRID_TYPE_FLOAT,
                    buf,
                    acc,
                    ijk + offset
                );
                v[x][y][z] = pnanovdb_read_float(buf, addr);
            }
        }
    }

    return v;
}

// Compute trilinear gradient from 2x2x2 stencil
// uvw: fractional position within the voxel [0,1]^3
// v: 2x2x2 stencil values indexed as [x][y][z]
fn pnanovdb_trilinear_gradient(
    uvw: vec3f,
    v: array<array<array<f32, 2>, 2>, 2>
) -> vec3f {
    // Compute differences along Z axis for all 4 XY corners
    var D: array<f32, 4>;
    D[0] = v[0][0][1] - v[0][0][0];
    D[1] = v[0][1][1] - v[0][1][0];
    D[2] = v[1][0][1] - v[1][0][0];
    D[3] = v[1][1][1] - v[1][1][0];

    // Z component: interpolate the Z differences
    let grad_z = mix(mix(D[0], D[1], uvw.y), mix(D[2], D[3], uvw.y), uvw.x);

    // Interpolate along Z to get 4 values at the correct Z position
    let w = uvw.z;
    D[0] = v[0][0][0] + D[0] * w;
    D[1] = v[0][1][0] + D[1] * w;
    D[2] = v[1][0][0] + D[2] * w;
    D[3] = v[1][1][0] + D[3] * w;

    // X component: difference between interpolated X edges
    let grad_x = mix(D[2], D[3], uvw.y) - mix(D[0], D[1], uvw.y);

    // Y component: difference between interpolated Y edges
    let grad_y = mix(D[1] - D[0], D[3] - D[2], uvw.x);

    return vec3f(grad_x, grad_y, grad_z);
}
