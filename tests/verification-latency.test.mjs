import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs/promises';
import vm from 'node:vm';

// Run the production polling loop with deterministic CDP results and a virtual clock.
const source = await fs.readFile(new URL('../engine/scripts/injector.mjs', import.meta.url), 'utf8');
const loop = source.slice(source.indexOf('async function waitForVerifiedSession('), source.indexOf('\nasync function capture('));
const hidden = {pass:false, installed:true, stylePresent:true, version:'1', expectedVersion:'1',
  themeId:'custom', expectedThemeId:'custom', revision:'new', expectedRevision:'new',
  documentHidden:true, documentVisibility:'hidden', businessClassPollution:0,
  readiness:{structurePass:true,viewportPass:true}};
async function run(results, returnOnHidden) {
  let elapsed=0, calls=0;
  const context=vm.createContext({Date:{now:()=>elapsed},setTimeout:fn=>{elapsed+=500;fn();},
    verifySession:async()=>structuredClone(results[Math.min(calls++,results.length-1)])});
  vm.runInContext(loop,context);
  const result=await context.waitForVerifiedSession({},'target',30000,'custom','new',true,returnOnHidden);
  return {result,elapsed,calls};
}
test('hidden verified payload returns promptly to startup for activation, without claiming success',async()=>{
  const {result,elapsed,calls}=await run([hidden],true);
  assert.equal(result.pass,false);
  assert.equal(elapsed,0,'must not burn the 30-second verification budget on a hidden window');
  assert.equal(calls,1);
});
test('visible slow media and wrong hidden revision still receive the retry budget',async()=>{
  for(const first of [{...hidden,documentHidden:false,documentVisibility:'visible'},{...hidden,revision:'old'}]){
    const {result,calls}=await run([first,{pass:true}],true);
    assert.equal(result.pass,true);assert.equal(calls,2);
  }
});
test('one-shot apply still waits for visible rendering',async()=>{
  const {result,calls}=await run([hidden,{pass:true}],false);
  assert.equal(result.pass,true);assert.equal(calls,2);
});
test('hidden incomplete or mismatched payloads are not classified as ready for activation',async()=>{
  for(const change of [{installed:false},{stylePresent:false},{version:'old'},{themeId:'wrong'},
    {businessClassPollution:1},{readiness:{structurePass:false,viewportPass:true}},
    {readiness:{structurePass:true,viewportPass:false}}]){
    const {result,calls}=await run([{...hidden,...change},{pass:true}],true);
    assert.equal(result.pass,true);assert.equal(calls,2);
  }
});
test('an already-ready one-shot apply verifies immediately without a fixed sleep',async()=>{
  let slept=0, verified=0, applied=0;
  const body=source.slice(source.indexOf('async function runOneShot(options)'),source.indexOf('\nexport async function externalSourceUnavailable('));
  const session={close(){}};
  const context=vm.createContext({
    setTimeout:fn=>{slept++;fn();},console:{log(){}},process:{exitCode:0},
    connectCodexTargets:async()=>[{target:{id:'fixture'},session,probe:{markers:{}}}],
    shouldShowOperationUi:()=>false,loadPayload:async()=>({payload:'fixture',theme:{id:'custom'},revision:'new'}),
    applyToSession:async()=>{applied++;},waitForVerifiedSession:async()=>{verified++;return {pass:true};},
  });
  vm.runInContext(body,context);
  await context.runOneShot({mode:'once',timeoutMs:3000});
  assert.equal(applied,1);assert.equal(verified,1);
  assert.equal(slept,0,'readiness verification already handles media decoding; do not delay a ready image');
});
