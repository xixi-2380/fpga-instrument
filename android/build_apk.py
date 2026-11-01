"""Build development APK using official Android SDK tools, without Gradle.
Requires JDK17 with jdk.compiler, SDK Platform35 and Build-tools35.0.0.
Never builds FPGA or touches hardware. Generated signing key is development-only.
"""
import argparse,hashlib,json,os,pathlib,shutil,subprocess,xml.etree.ElementTree as ET,zipfile
p=argparse.ArgumentParser();p.add_argument('--sdk-root',required=True);p.add_argument('--out-dir',required=True)
a=p.parse_args();root=pathlib.Path(__file__).resolve().parent;sdk=pathlib.Path(a.sdk_root).resolve();out=pathlib.Path(a.out_dir).resolve();out.mkdir(parents=True,exist_ok=True)
tools=sdk/'build-tools/35.0.0';platform=sdk/'platforms/android-35/android.jar';classes=out/'classes';dex=out/'dex'
for folder in (classes,dex):
 if not folder.resolve().is_relative_to(out):raise ValueError('Output escaped build directory')
 if folder.exists():shutil.rmtree(folder)
 folder.mkdir()
suffix='.exe' if os.name=='nt' else ''
def run(name,cmd):
 r=subprocess.run([str(c) for c in cmd],capture_output=True,text=True,encoding='utf-8',errors='replace')
 (out/(name+'.log')).write_text(r.stdout+r.stderr,encoding='utf-8')
 if r.returncode:raise RuntimeError(name+' failed: '+r.stdout+r.stderr)
 print(name+' OK')
javac=shutil.which('javac');compile_cmd=[javac] if javac else ['java','-m','jdk.compiler/com.sun.tools.javac.Main']
sources=sorted((root/'app/src/main/java').rglob('*.java'))
run('javac',compile_cmd+['-encoding','UTF-8','-source','8','-target','8','-classpath',platform,'-d',classes]+sources)
run('d8',['java','-cp',tools/'lib/d8.jar','com.android.tools.r8.D8','--lib',platform,'--min-api','26','--output',dex]+sorted(classes.rglob('*.class')))
# AGP source uses namespace; aapt2 standalone requires an explicit manifest package.
ET.register_namespace('android','http://schemas.android.com/apk/res/android')
tree=ET.parse(root/'app/src/main/AndroidManifest.xml');tree.getroot().set('package','cn.whu.gaoshan')
# AGP normally injects this attribute for debug builds.
tree.find('application').set('{http://schemas.android.com/apk/res/android}debuggable','true')
manifest=out/'AndroidManifest.xml';tree.write(manifest,encoding='utf-8',xml_declaration=True)
unsigned=out/'unsigned.apk'
run('aapt2',[tools/('aapt2'+suffix),'link','-o',unsigned,'-I',platform,'--manifest',manifest,'--min-sdk-version','26','--target-sdk-version','35','--version-code','7','--version-name','0.4-midi-timbres'])
with zipfile.ZipFile(unsigned,'a',zipfile.ZIP_DEFLATED) as z:
 for d in sorted(dex.glob('*.dex')):z.write(d,d.name)
aligned=out/'aligned.apk';run('zipalign',[tools/('zipalign'+suffix),'-f','-p','4',unsigned,aligned])
key=out/'debug.keystore'
if not key.exists():run('keygen',[str(pathlib.Path(javac).parent/'keytool.exe') if javac else 'keytool','-genkeypair','-keystore',key,'-storepass','android','-keypass','android','-alias','androiddebugkey','-keyalg','RSA','-keysize','2048','-validity','3650','-dname','CN=Gaoshan Development, OU=FPGA, O=Student Project, C=CN'])
apk=out/'GaoshanScore-0.4-midi-timbres.apk';signer=['java','-jar',tools/'lib/apksigner.jar']
run('sign',signer+['sign','--ks',key,'--ks-key-alias','androiddebugkey','--ks-pass','pass:android','--key-pass','pass:android','--out',apk,aligned])
run('verify',signer+['verify','--verbose','--print-certs',apk])
run('manifest',[tools/('aapt2'+suffix),'dump','badging',apk])
metadata={'apk':apk.name,'sha256':hashlib.sha256(apk.read_bytes()).hexdigest(),'size':apk.stat().st_size,'build':'javac + D8 + aapt2 + zipalign + apksigner','min_sdk':26,'target_sdk':35,'java_sources':len(sources),'apk_device_run':'not performed','radio_fpga_test':'not performed'}
(out/'build_summary.json').write_text(json.dumps(metadata,ensure_ascii=False,indent=2),encoding='utf-8')
print(apk)
