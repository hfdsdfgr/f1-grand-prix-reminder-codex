// The offline HTML is the editable geometry source; export the same meshes for mobile evaluation.
// Run: node prototypes/build-car-asset.mjs
import {readFile,mkdir,writeFile} from 'node:fs/promises';
import vm from 'node:vm';
import assert from 'node:assert/strict';
const html=await readFile(new URL('car-viewer.html',import.meta.url),'utf8');
const start=html.indexOf('const components ='),end=html.indexOf('const $ =');
assert.ok(start>0&&end>start);
const {components,materials}=vm.runInNewContext(html.slice(start,end)+';({components,materials})',{}, {timeout:2000});
const palette={...materials.neutral,tyre:'#303338',hub:'#707980'};
const names=Object.keys(palette),chunks=[],views=[],accessors=[],meshes=[];let offset=0;
function attribute(values,type){
 const floats=new Float32Array(values),bytes=Buffer.from(floats.buffer);chunks.push(bytes);
 const view=views.length;views.push({buffer:0,byteOffset:offset,byteLength:bytes.length,target:34962});offset+=bytes.length;
 const lo=[Infinity,Infinity,Infinity],hi=[-Infinity,-Infinity,-Infinity];values.forEach((v,i)=>{assert.ok(Number.isFinite(v));lo[i%3]=Math.min(lo[i%3],v);hi[i%3]=Math.max(hi[i%3],v)});
 accessors.push({bufferView:view,componentType:5126,count:values.length/3,type:'VEC3',...(type==='position'?{min:lo,max:hi}:{})});return accessors.length-1;
}
for(const component of components){
 const primitives=[];
 for(const material of names){
  const positions=[],normals=[];
  for(const face of component.faces.filter(f=>f.material===material))for(let i=1;i<face.points.length-1;i++){
   const points=[face.points[0],face.points[i],face.points[i+1]],u=points[1].map((v,j)=>v-points[0][j]),v=points[2].map((v,j)=>v-points[0][j]);
   const n=[u[1]*v[2]-u[2]*v[1],u[2]*v[0]-u[0]*v[2],u[0]*v[1]-u[1]*v[0]],len=Math.hypot(...n);if(len<1e-10)continue;
   for(const p of points){positions.push(...p);normals.push(...n.map(v=>v/len));}
  }
  if(positions.length)primitives.push({attributes:{POSITION:attribute(positions,'position'),NORMAL:attribute(normals,'normal')},material:names.indexOf(material),mode:4});
 }
 meshes.push({name:component.id,primitives});
}
assert.equal(meshes.length,13);assert.ok(meshes.every(m=>m.primitives.length));
const data={asset:{version:'2.0',generator:'GrandPrixReminder illustration prototype'},scene:0,scenes:[{nodes:components.map((_,i)=>i)}],nodes:components.map((c,i)=>({name:c.id,mesh:i,extras:{anchor:c.anchor,illustration:true}})),meshes,materials:names.map(name=>({name,doubleSided:true,pbrMetallicRoughness:{baseColorFactor:[...([1,3,5].map(i=>parseInt(palette[name].slice(i,i+2),16)/255)),1],metallicFactor:0,roughnessFactor:.8}})),buffers:[{byteLength:offset}],bufferViews:views,accessors};
const json=Buffer.from(JSON.stringify(data)),padding=(4-json.length%4)%4,jsonChunk=Buffer.concat([json,Buffer.alloc(padding,32)]),binary=Buffer.concat(chunks),header=Buffer.alloc(12),jh=Buffer.alloc(8),bh=Buffer.alloc(8);
header.writeUInt32LE(0x46546c67);header.writeUInt32LE(2,4);header.writeUInt32LE(12+8+jsonChunk.length+8+binary.length,8);jh.writeUInt32LE(jsonChunk.length);jh.writeUInt32LE(0x4e4f534a,4);bh.writeUInt32LE(binary.length);bh.writeUInt32LE(0x004e4942,4);
await mkdir(new URL('assets/',import.meta.url),{recursive:true});
const glb=Buffer.concat([header,jh,jsonChunk,bh,binary]);
await writeFile(new URL('assets/universal-car.glb',import.meta.url),glb);
console.log(`Exported ${glb.length} bytes; ${meshes.length} named meshes; ${offset/24/3} triangles. Generic illustration, not a sourced generation.`);
// Native Flutter consumes the same faces, materials and anchors without a WebView.
const english = [
 ['Front Wing','Multi-element wings at the front of the car.','Guide airflow and generate front downforce.','Affect front grip and aerodynamic balance.'],
 ['Nose','The narrow body structure ahead of the cockpit.','Connects the forward body and influences nearby airflow.','Works with the front wing and chassis layout.'],
 ['Front Suspension','Links connecting the front wheels to the chassis.','Control wheel motion and transmit loads.','Influence tyre contact and car attitude.'],
 ['Front Tyres','The front tyre and wheel assemblies.','Transmit steering, braking and lateral forces.','Grip depends on temperature, pressure and wear, among other factors.'],
 ['Halo','A protective structure around the driver’s head.','Provides additional cockpit protection.','A safety structure, not an internal powertrain component.'],
 ['Cockpit','The space occupied by the driver.','Accommodates driving controls and restraint systems.','Its layout must support safety and operation.'],
 ['Sidepods','The bodywork on either side of the cockpit.','Accommodate cooling components and guide external airflow.','Cooling requirements and aerodynamic design interact.'],
 ['Floor','The broad structure beneath the car.','Contributes downforce and guides underbody airflow.','Its behaviour depends on ride height and surrounding flow.'],
 ['Engine Cover','External bodywork behind the cockpit.','Encloses the powertrain area and shapes external airflow.','Cooling and packaging constrain its shape; this model omits internal machinery.'],
 ['Rear Suspension','Links connecting the rear wheels to the car.','Transmit loads and control rear wheel motion.','Related to traction, tyre contact and car attitude.'],
 ['Rear Tyres','The rear tyre and wheel assemblies.','Transmit driving, braking and lateral forces.','Temperature, wear and loads affect available grip.'],
 ['Beam Wing','Wing surfaces below the rear wing.','Help organise airflow at the rear of the car.','Their shape depends on the technical rules and car design.'],
 ['Rear Wing','The upper wing assembly at the rear.','Generates rear downforce and also creates drag.','Design balances cornering grip and straight-line performance.']
];
const carStart=html.indexOf('const carModels='),carEnd=html.indexOf(';',carStart);
const carModels=vm.runInNewContext(html.slice(carStart,carEnd)+';carModels');
const mobileData={components:components.map((c,i)=>({...c,en:english[i]})),materials,carModels};
await mkdir(new URL('../mobile/assets/evolution/',import.meta.url),{recursive:true});
await writeFile(new URL('../mobile/assets/evolution/car.json',import.meta.url),JSON.stringify(mobileData,(_,v)=>typeof v==='number'?Math.round(v*1e6)/1e6:v));
