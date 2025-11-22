import { vec3, mat4 } from 'wgpu-matrix';
import DisplayShader from "./blit.wgsl";
import ComputeShader from "./compute.wgsl";
import PNanoVDBShader from "./../pnanovdb.wgsl";
import { loadNanoVDB } from './lib/loader';
import { ArcballCamera, WASDCamera } from './lib/camera';
import { createInputHandler } from "./lib/input";
import { controls, pauseController, cameraController, highDPIController, rotationController } from './lib/gui';
import { TimestampQueryManager } from './lib/TimestampQueryManager';
import { Stats } from './lib/Stats';

const canvas = document.getElementById("canvas") as HTMLCanvasElement;
const infoTextElement = document.getElementById("info-text")!;

if (!canvas) {
  throw new Error("No canvas found.");
}
if (!navigator.gpu) {
  throw new Error("WebGPU not supported on this browser.");
}
console.log("WebGPU is supported!");

const adapter = await navigator.gpu.requestAdapter({
  featureLevel: 'compatibility',
});
if (!adapter) {
  throw new Error("No appropriate GPUAdapter found.");
}

let width = canvas.width;
let height = canvas.height;
let raytracedTexture: GPUTexture;
let displayBindGroup: GPUBindGroup;
let computeBindGroup: GPUBindGroup;

// Set canvas to fullscreen size and recreate GPU resources
function resizeCanvas() {
  const pixelRatio = controls.highDPI ? window.devicePixelRatio : 1.0;
  canvas.width = window.innerWidth * pixelRatio;
  canvas.height = window.innerHeight * pixelRatio;
  width = canvas.width;
  height = canvas.height;

  // Will recreate GPU resources after they're initially created
  if (raytracedTexture) {
    createGPUResources();
  }
}

resizeCanvas();
window.addEventListener('resize', resizeCanvas);

// Update canvas size when High DPI setting changes
highDPIController.onChange(() => {
  resizeCanvas();
});

// The use of timestamps require a dedicated adapter feature:
// The adapter may or may not support timestamp queries. If not, we simply
// don't measure timestamps and deactivate the timer display.
const supportsTimestampQueries = adapter?.features.has('timestamp-query');

const device = await adapter.requestDevice({
  // We request a device that has support for timestamp queries
  requiredFeatures: supportsTimestampQueries ? ['timestamp-query'] : [],
});
device.addEventListener('uncapturederror', event => {
  console.log(event.error);
});

const context = canvas.getContext("webgpu");
if (!context) {
  throw new Error("No context found.");
}

var stats = new Stats();
var gpuPanel = stats.addPanel(new Stats.Panel('GPU', '#ff8', '#221'));
document.body.appendChild(stats.dom);

// GPU-side timer and the CPU-side counter where we accumulate statistics:
// NB: Look for 'timestampQueryManager' in this file to locate parts of this
// snippets that are related to timestamps. Most of the logic is in
// TimestampQueryManager.ts.
const timestampQueryManager = new TimestampQueryManager(device, (elapsedNs) => {
  // Convert from nanoseconds to milliseconds:
  const elapsedMs = Number(elapsedNs) * 1e-6;
  gpuPanel.update(elapsedMs, 16); // 16ms = 60fps target
});

const canvasFormat = navigator.gpu.getPreferredCanvasFormat();
context.configure({
  device: device,
  format: canvasFormat,
});

// https://webgpufundamentals.org/webgpu/lessons/webgpu-large-triangle-to-cover-clip-space.html
const vertices = new Float32Array([
  // X,  Y,
  -1, 3, // Triangle 1
  3, -1,
  -1, -1,
]);

const vertexBuffer = device.createBuffer({
  // Labels are useful for debugging.
  label: "Display vertices",
  // 4 bytes * 6 vertices = 24 bytes.
  size: vertices.byteLength,
  // The buffer will be used as the source of vertex data.
  usage: GPUBufferUsage.VERTEX | GPUBufferUsage.COPY_DST,
});
device.queue.writeBuffer(vertexBuffer, /* offset */ 0, vertices);

const vertexBufferLayout: GPUVertexBufferLayout = {
  // 2 floats for position.
  arrayStride: 8,
  attributes: [{
    format: "float32x2",
    offset: 0,
    shaderLocation: 0, // Position, see vertex shader
  }],
};

// Create size-dependent GPU resources
function createGPUResources() {
  // Destroy old texture if it exists
  if (raytracedTexture) {
    raytracedTexture.destroy();
  }

  // Create the texture (output from compute shader)
  raytracedTexture = device.createTexture({
    size: [width, height],
    format: 'rgba8unorm',
    usage: GPUTextureUsage.STORAGE_BINDING |
      GPUTextureUsage.TEXTURE_BINDING |
      GPUTextureUsage.COPY_SRC
  });

  // Recreate bind groups that depend on the texture
  displayBindGroup = device.createBindGroup({
    label: "Display bind group",
    layout: displayPipeline.getBindGroupLayout(0),
    entries: [
      {
        binding: 0, // Corresponds to @binding(0) in the shader.
        resource: raytracedTexture.createView()
      },
      {
        binding: 1, // Corresponds to @binding(1) in the shader.
        resource: displaySampler
      }
    ]
  });

  computeBindGroup = device.createBindGroup({
    label: 'Raytracing Bind Group',
    layout: computeBindGroupLayout,
    entries: [
      {
        binding: 0,
        resource: raytracedTexture.createView()
      },
      {
        binding: 1,
        resource: {
          buffer: inputBuffer
        }
      },
      {
        binding: 2,
        resource: {
          buffer: nanoVDBBuffer
        }
      }
    ]
  });
}

// Create the sampler
const displaySampler = device.createSampler({
  addressModeU: 'clamp-to-edge',
  addressModeV: 'clamp-to-edge',
  magFilter: 'linear',
  minFilter: 'linear',
});

const displayShaderModule = device.createShaderModule({
  label: "Display shader",
  code: DisplayShader,
});

const displayPipeline = device.createRenderPipeline({
  label: "Display pipeline",
  layout: "auto",
  vertex: {
    module: displayShaderModule,
    entryPoint: "vertexMain",
    buffers: [vertexBufferLayout]
  },
  fragment: {
    module: displayShaderModule,
    entryPoint: "fragmentMain",
    targets: [{
      format: canvasFormat,
    }],
  },
});

const inputHandler = createInputHandler(window, canvas);

// Load NanoVDB data
infoTextElement.textContent = "Loading bunny.nvdb.gz...";
const nanoVDBResult = await loadNanoVDB('./bunny.nvdb.gz');
const nanoVDBBuffer = device.createBuffer({
  label: 'NanoVDB Buffer',
  size: nanoVDBResult.gridData.byteLength,
  usage: GPUBufferUsage.STORAGE | GPUBufferUsage.COPY_DST
});
device.queue.writeBuffer(nanoVDBBuffer, 0, nanoVDBResult.gridData);

const fov = (2 * Math.PI) / 5; // 72 degrees
const fovScaled = Math.tan(fov / 2);
const initialCameraPosition = vec3.create(3, 2, 5);
const cameras = {
  arcball: new ArcballCamera({ position: initialCameraPosition }),
  WASD: new WASDCamera({ position: initialCameraPosition }),
};
let currentCamera = cameras[controls.cameraType];

cameraController.onChange((newCameraType: 'arcball' | 'WASD') => {
  // Copy the camera matrix from old to new
  const oldCamera = currentCamera;
  const newCamera = cameras[newCameraType];
  newCamera.matrix = oldCamera.matrix;
  currentCamera = newCamera;
  controls.cameraType = newCameraType;
});


const InputValues = new ArrayBuffer(256);
const InputViews = {
  camera_matrix: new Float32Array(InputValues, 0, 16),
  fov_scale: new Float32Array(InputValues, 64, 1),
  time_delta: new Float32Array(InputValues, 68, 1),
  nanovdb_offset: new Uint32Array(InputValues, 72, 1),
  nanovdb_size: new Uint32Array(InputValues, 76, 1),
  nanovdb_grid_index: new Uint32Array(InputValues, 80, 1),
  nanovdb_bbox_min: new Float32Array(InputValues, 96, 3),
  nanovdb_bbox_max: new Float32Array(InputValues, 112, 3),
  nanovdb_matrix: new Float32Array(InputValues, 128, 16),
  nanovdb_inverse_matrix: new Float32Array(InputValues, 192, 16),
};

const inputBuffer = device.createBuffer({
  label: 'Input Uniforms',
  size: InputValues.byteLength,
  usage: GPUBufferUsage.UNIFORM | GPUBufferUsage.COPY_DST
});

// Initialize nanovdb values
InputViews.fov_scale[0] = fovScaled;
InputViews.nanovdb_offset[0] = 0; // Start at beginning of buffer
InputViews.nanovdb_size[0] = Math.ceil(nanoVDBResult.gridData.byteLength / 4); // Size in 32-bit words
InputViews.nanovdb_grid_index[0] = 0; // First (and only) grid

// Set bounding box from loaded data
InputViews.nanovdb_bbox_min.set(nanoVDBResult.worldBBox.slice(0, 3)); // min x,y,z
InputViews.nanovdb_bbox_max.set(nanoVDBResult.worldBBox.slice(3, 6)); // max x,y,z

// Function to update nanovdb transformation matrices
function updateNanoVDBMatrices() {
  // Create transformation matrix (scale + translation + rotation)
  const nanoVDBMatrix = mat4.identity();
  mat4.translation(vec3.create(-2, 12, 0), nanoVDBMatrix);
  mat4.scale(nanoVDBMatrix, vec3.create(6, 6, 6), nanoVDBMatrix);
  
  // Apply Y-axis rotation from GUI
  const rotationRadians = (controls.bunnyRotation * Math.PI) / 180;
  mat4.rotateY(nanoVDBMatrix, rotationRadians, nanoVDBMatrix);
  
  const nanoVDBInverseMatrix = mat4.inverse(nanoVDBMatrix);
  InputViews.nanovdb_matrix.set(nanoVDBMatrix);
  InputViews.nanovdb_inverse_matrix.set(nanoVDBInverseMatrix);
}

// Initial matrix setup
updateNanoVDBMatrices();

// Update matrices when rotation changes
rotationController.onChange(() => {
  updateNanoVDBMatrices();
});

// Update info display
const sizeMB = (InputViews.nanovdb_size[0] * 4 / 1024 / 1024).toFixed(1);
const bboxSize = [
  (InputViews.nanovdb_bbox_max[0] - InputViews.nanovdb_bbox_min[0]).toFixed(1),
  (InputViews.nanovdb_bbox_max[1] - InputViews.nanovdb_bbox_min[1]).toFixed(1),
  (InputViews.nanovdb_bbox_max[2] - InputViews.nanovdb_bbox_min[2]).toFixed(1)
];

infoTextElement.textContent = `WebGPU NanoVDB
bunny.nvdb ${sizeMB}MB
Grid: ${bboxSize[0]} × ${bboxSize[1]} × ${bboxSize[2]} units
Voxels: ${nanoVDBResult.metadata?.voxelCount}`;
function updateInput(deltaTime: number) {
  // Update time delta
  InputViews.time_delta[0] = deltaTime;

  // Update camera
  currentCamera.update(deltaTime, inputHandler());
  InputViews.camera_matrix.set(currentCamera.matrix);

  // Write entire input buffer at once
  device.queue.writeBuffer(inputBuffer, 0, InputValues);
}

// Combine PNanoVDB shader library with compute shader
const combinedShader = PNanoVDBShader + '\n' + ComputeShader;

const computeShaderModule = device.createShaderModule({
  label: 'Raytracing Compute Shader',
  code: combinedShader,
});

// Check for shader compilation errors
const shaderInfo = await computeShaderModule.getCompilationInfo();
if (shaderInfo.messages.length > 0) {
  console.error('Shader compilation messages:', shaderInfo.messages);
  for (const message of shaderInfo.messages) {
    console.log(`${message.type} at line ${message.lineNum}: ${message.message}`);
    if (message.type === 'error') {
      alert(`Shader error at line ${message.lineNum}: ${message.message}`);
    }
  }
}

// Create explicit bind group layout
const computeBindGroupLayout = device.createBindGroupLayout({
  label: 'Compute Bind Group Layout',
  entries: [
    {
      binding: 0,
      visibility: GPUShaderStage.COMPUTE,
      storageTexture: {
        access: 'write-only',
        format: 'rgba8unorm',
        viewDimension: '2d'
      }
    },
    {
      binding: 1,
      visibility: GPUShaderStage.COMPUTE,
      buffer: {
        type: 'uniform'
      }
    },
    {
      binding: 2,
      visibility: GPUShaderStage.COMPUTE,
      buffer: {
        type: 'read-only-storage'
      }
    },
  ]
});

const computePipelineLayout = device.createPipelineLayout({
  label: 'Compute Pipeline Layout',
  bindGroupLayouts: [computeBindGroupLayout]
});

const computePipeline = await device.createComputePipelineAsync({
  label: 'Raytracing Compute Pipeline',
  layout: computePipelineLayout,
  compute: {
    module: computeShaderModule,
    entryPoint: 'computeMain'
  }
}).catch((error) => {
  console.error('Pipeline creation failed:', error);
  alert(`Pipeline error: ${error.message}`);
  throw error;
});

console.log('Pipeline created, getting bind group layout...');

const computePassDescriptor: GPUComputePassDescriptor = {
  label: "Compute pass",
}
timestampQueryManager.addTimestampWrite(computePassDescriptor);

// Initial creation of GPU resources (after all dependencies are defined)
createGPUResources();

const colorAttachment: GPURenderPassColorAttachment = {
  view: context.getCurrentTexture().createView(), // Assigned on render 
  clearValue: { r: 0, g: 0, b: 0, a: 1 },
  loadOp: 'clear',
  storeOp: 'store',
}

const renderPassDescriptor: GPURenderPassDescriptor = {
  label: "Display pass",
  colorAttachments: [colorAttachment],
}

let lastFrameMS = (performance || Date).now();
function requestFrame() {
  if (!context) {
    throw new Error("No context found.");
  }
  const beginTime = stats.begin();
  const deltaTime = (beginTime - lastFrameMS) / 1000;
  lastFrameMS = beginTime;

  const encoder = device.createCommandEncoder({ label: "Command Encoder" });

  // Start a compute pass.
  const computePass = encoder.beginComputePass(computePassDescriptor);
  computePass.setPipeline(computePipeline);
  computePass.setBindGroup(0, computeBindGroup);
  const workgroups_x = Math.ceil(width / 16);
  const workgroups_y = Math.ceil(height / 16);
  computePass.dispatchWorkgroups(workgroups_x, workgroups_y, 1);

  computePass.end();

  // Start a display pass.
  colorAttachment.view = context.getCurrentTexture().createView();
  const displayPass = encoder.beginRenderPass(renderPassDescriptor);
  displayPass.setPipeline(displayPipeline);
  displayPass.setVertexBuffer(0, vertexBuffer);
  displayPass.setBindGroup(0, displayBindGroup);
  displayPass.draw(3, 1, 0, 0);
  displayPass.end();

  updateInput(deltaTime);

  // Resolve timestamp queries, so that their result is available in
  // a GPU-side buffer.
  timestampQueryManager.resolve(encoder);

  // Finish the command buffer and immediately submit it.
  device.queue.submit([encoder.finish()]);

  // Try to download the time stamp.
  timestampQueryManager.tryInitiateTimestampDownload();
  stats.end();
}

// Pause/resume functionality. UserequestAnimationFrame for optimal frame timing.
let animationId: number | null = null;

function renderLoop() {
  if (animationId === null) return;
  requestFrame();
  animationId = requestAnimationFrame(renderLoop);
}

function startRenderLoop() {
  animationId = requestAnimationFrame(renderLoop);
}

function stopRenderLoop() {
  if (animationId !== null) {
    cancelAnimationFrame(animationId);
    animationId = null;
  }
}

pauseController.onChange((paused: boolean) => {
  if (paused) {
    stopRenderLoop();
  } else {
    startRenderLoop();
  }
})

// Start the render loop
startRenderLoop();
