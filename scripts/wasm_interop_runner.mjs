import { readFileSync, writeFileSync } from "node:fs";

function usage() {
  console.error(
    "usage:\n" +
      "  node scripts/wasm_interop_runner.mjs <wasm> fixture <out-file>\n" +
      "  node scripts/wasm_interop_runner.mjs <wasm> roundtrip <in-file> <out-file>"
  );
  process.exit(2);
}

const args = process.argv.slice(2);
if (args.length < 3) usage();

const wasmPath = args[0];
const mode = args[1];

const wasmBytes = readFileSync(wasmPath);
const { instance } = await WebAssembly.instantiate(wasmBytes, {});
const e = instance.exports;

if (!e.memory) {
  throw new Error("wasm module does not export memory");
}

const memory = new Uint8Array(e.memory.buffer);
const inputPtr = Number(e.rawr_input_ptr());
const inputCap = Number(e.rawr_input_capacity());
const outputPtr = Number(e.rawr_output_ptr());

if (mode === "fixture") {
  if (args.length !== 3) usage();
  const outFile = args[2];
  const outLen = Number(e.rawr_fixture_serialize());
  if (outLen <= 0) {
    throw new Error("rawr_fixture_serialize failed");
  }
  writeFileSync(outFile, memory.subarray(outputPtr, outputPtr + outLen));
  process.exit(0);
}

if (mode === "roundtrip") {
  if (args.length !== 4) usage();
  const inFile = args[2];
  const outFile = args[3];
  const input = readFileSync(inFile);

  if (input.length > inputCap) {
    throw new Error(`input too large for wasm buffer: ${input.length} > ${inputCap}`);
  }

  memory.set(input, inputPtr);
  const outLen = Number(e.rawr_roundtrip_input(input.length));
  if (outLen <= 0) {
    throw new Error("rawr_roundtrip_input failed");
  }

  writeFileSync(outFile, memory.subarray(outputPtr, outputPtr + outLen));
  process.exit(0);
}

usage();
