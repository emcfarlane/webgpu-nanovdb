// Loader for NanoVDB files in a web-based 3D viewer using TypeScript and Fetch API.

// NanoVDB file format constants
const NANOVDB_MAGIC_FILE = 0x324244566f6e614en; // "NanoVDB2" in hex - little endian (uint64_t)
const NANOVDB_MAGIC_GRID = 0x314244566f6e614en; // "NanoVDB1" in hex - little endian (uint64_t)

interface FileHeader {
  magic: bigint;
  versionMajor: number;
  versionMinor: number;
  versionPatch: number;
  gridCount: number;
  codec: number;
}

interface FileMetaData {
  gridSize: bigint;
  fileSize: bigint;
  nameKey: bigint;
  voxelCount: bigint;
  gridType: number;
  gridClass: number;
  nameSize: number;
  codec: number;
  version: number;
}

interface NanoVDBData {
  gridData: ArrayBuffer;
  worldBBox: Float32Array; // [minX, minY, minZ, maxX, maxY, maxZ]
  metadata?: FileMetaData;
}

export async function loadNanoVDB(url: string): Promise<NanoVDBData> {
  const response = await fetch(url);
  if (!response.ok) {
    throw new Error(`Failed to load NanoVDB file ${url}: ${response.statusText}`);
  }

  let data: ArrayBuffer;

  // Check if file is gzipped based on URL extension
  if (url.endsWith('.gz')) {
    console.log('Decompressing gzipped NanoVDB file...');
    const compressedData = await response.arrayBuffer();
    console.log(`Loaded compressed NanoVDB file: ${compressedData.byteLength} bytes`);

    // Check if DecompressionStream is supported
    if (typeof DecompressionStream === 'undefined') {
      throw new Error('Gzip decompression not supported in this browser. Please use a modern browser with Compression Streams API support.');
    }

    // Decompress using native Compression Streams API
    const stream = new Response(compressedData).body!
      .pipeThrough(new DecompressionStream('gzip'));
    data = await new Response(stream).arrayBuffer();
    console.log(`Decompressed NanoVDB file: ${data.byteLength} bytes`);
  } else {
    data = await response.arrayBuffer();
    console.log(`Loaded raw NanoVDB file: ${data.byteLength} bytes`);
  }

  const view = new DataView(data);
  let offset = 0;

  // Read FileHeader (16 bytes)
  const version = view.getUint32(offset + 8, true);
  const header: FileHeader = {
    magic: view.getBigUint64(offset, true), // little endian
    versionMajor: version >> 21,
    versionMinor: (version >> 10) & 0x7ff,
    versionPatch: version & 0x3ff,
    gridCount: view.getUint16(offset + 12, true),
    codec: view.getUint16(offset + 14, true)
  };
  offset += 16;

  console.log('NanoVDB FileHeader:');
  console.log(`  Magic: 0x${header.magic.toString(16)}`);
  console.log(`  Version: ${header.versionMajor}.${header.versionMinor}.${header.versionPatch}`);
  console.log(`  Grid Count: ${header.gridCount}`);
  console.log(`  Codec: ${header.codec}`);

  // Validate magic number
  if (header.magic !== NANOVDB_MAGIC_FILE) {
    throw new Error(`Invalid NanoVDB magic number: 0x${header.magic.toString(16)}`);
  }

  if (header.gridCount === 0) {
    throw new Error('NanoVDB file contains no grids');
  }

  // Read first grid's metadata (176 bytes)
  const metadata: FileMetaData = {
    gridSize: view.getBigUint64(offset, true),
    fileSize: view.getBigUint64(offset + 8, true),
    nameKey: view.getBigUint64(offset + 16, true),
    voxelCount: view.getBigUint64(offset + 24, true),
    gridType: view.getUint32(offset + 32, true),
    gridClass: view.getUint32(offset + 36, true),
    // Skip worldBBox (48 bytes) and indexBBox (24 bytes) and voxelSize (24 bytes)
    nameSize: view.getUint32(offset + 136, true),
    // Skip nodeCount (16 bytes) and tileCount (12 bytes)
    codec: view.getUint16(offset + 168, true),
    version: view.getUint32(offset + 172, true)
  };

  // Read world bounding box (6 f64 values, 48 bytes total, starts after gridClass)
  const worldBBoxOffset = offset + 40; // After gridType(4) + gridClass(4) = 8 bytes from start
  const worldBBoxF64 = new Float64Array(data, worldBBoxOffset, 6);
  const worldBBox = new Float32Array([
    worldBBoxF64[0], worldBBoxF64[1], worldBBoxF64[2], // min x,y,z
    worldBBoxF64[3], worldBBoxF64[4], worldBBoxF64[5]  // max x,y,z
  ]);

  console.log('NanoVDB World BBox (f64→f32):');
  console.log(`  Min: [${worldBBox[0]}, ${worldBBox[1]}, ${worldBBox[2]}]`);
  console.log(`  Max: [${worldBBox[3]}, ${worldBBox[4]}, ${worldBBox[5]}]`);

  offset += 176;

  console.log('NanoVDB FileMetaData:');
  console.log(`  Grid Size: ${metadata.gridSize} bytes`);
  console.log(`  File Size: ${metadata.fileSize} bytes`);
  console.log(`  Name Key: 0x${metadata.nameKey.toString(16)}`);
  console.log(`  Voxel Count: ${metadata.voxelCount}`);
  console.log(`  Grid Type: ${metadata.gridType}`);
  console.log(`  Grid Class: ${metadata.gridClass}`);
  console.log(`  Name Size: ${metadata.nameSize} bytes`);
  console.log(`  Codec: ${metadata.codec}`);

  // Read grid name
  const gridNameBytes = new Uint8Array(data, offset, metadata.nameSize);
  const gridName = new TextDecoder().decode(gridNameBytes);
  offset += metadata.nameSize;
  console.log(`  Grid Name: "${gridName}"`);

  // Extract grid data
  const gridDataSize = Number(metadata.gridSize);
  console.log(`Extracting grid data: ${gridDataSize} bytes at offset ${offset}`);

  if (offset + gridDataSize > data.byteLength) {
    throw new Error(`Grid data extends beyond file: need ${offset + gridDataSize}, have ${data.byteLength}`);
  }

  const gridData = data.slice(offset, offset + gridDataSize);
  // Validate grid magic number at the start of grid data
  const gridView = new DataView(gridData);
  const gridMagic = gridView.getBigUint64(0, true); // little endian
  console.log(`Grid magic: 0x${gridMagic.toString(16)}`);
  if (gridMagic !== NANOVDB_MAGIC_GRID) {
    throw new Error(`Invalid NanoVDB grid magic number: 0x${gridMagic.toString(16)}, expected: 0x${NANOVDB_MAGIC_GRID.toString(16)}`);
  }

  // Pad to 4-byte alignment
  const paddedSize = Math.ceil(gridData.byteLength / 4) * 4;
  let finalGridData: ArrayBuffer;

  if (paddedSize === gridData.byteLength) {
    console.log(`Grid data extracted: ${gridData.byteLength} bytes`);
    finalGridData = gridData;
  } else {
    // Create padded buffer
    const paddedBuffer = new ArrayBuffer(paddedSize);
    const paddedView = new Uint8Array(paddedBuffer);
    paddedView.set(new Uint8Array(gridData));
    console.log(`Grid data extracted: ${gridData.byteLength} bytes (padded to ${paddedSize})`);
    finalGridData = paddedBuffer;
  }

  return {
    gridData: finalGridData,
    worldBBox: worldBBox,
    metadata: metadata
  };
}
