const fs=require('fs'),vm=require('vm'),path=require('path');
const source=process.argv[2]||path.resolve(__dirname,'../reference/pharmacare-preview28-fixed.html');
const output=process.argv[3]||path.resolve(__dirname,'../reference/i18n.json');
const L=fs.readFileSync(source,'utf8').split('\n');
const ctx={EN:{},AM:{},OM:{},TI:{},CATS:{}};vm.createContext(ctx);
// string-aware balance scanner for ( { [
function balanced(src){let d=0,q=null,esc=false;for(const c of src){if(q){if(esc){esc=false}else if(c==='\\')esc=true;else if(c===q)q=null;continue}
 if(c==="'"||c==='"'||c==='`'){q=c;continue}if('({['.includes(c))d++;else if(')}]'.includes(c))d--}return d===0&&!q}
let ok=0,bad=[];
for(let i=0;i<L.length;i++){
  const l=L[i];
  if(/^(const CATS=|const EN=|const AM=|Object\.keys\(CATS\)|Object\.assign\((EN|AM|OM|TI),)/.test(l)){
    let src=l,j=i;
    while(!balanced(src)&&j<L.length-1){j++;src+='\n'+L[j]}
    src=src.replace(/^const (CATS|EN|AM)=/,'$1=');
    try{vm.runInContext(src,ctx);ok++}catch(e){bad.push([i+1,e.message])}
    i=j;
  }
}
console.log('ok',ok,'bad',JSON.stringify(bad));
for(const k of ['EN','AM','OM','TI']) console.log(k,Object.keys(ctx[k]).length);
const old=fs.existsSync(output)?JSON.parse(fs.readFileSync(output,'utf8')):{};
const merge=(key)=>Object.assign({},old[key]||{},ctx[key]);
const result={EN:merge('EN'),AM:merge('AM'),OM:merge('OM'),TI:merge('TI'),CATS:merge('CATS')};
fs.writeFileSync(output,JSON.stringify(result,null,2)+'\n');
const dartString=value=>JSON.stringify(value).replace(/\\u([0-9a-f]{4})/gi,'\\u$1');
const localeFiles={
  EN:['enStrings','English (en)'],
  AM:['amStrings','Amharic (am)'],
  OM:['omStrings','Afaan Oromo (om). Partial in the preview; missing keys fall back to English'],
  TI:['tiStrings','Tigrinya (ti). Partial in the preview; missing keys fall back to English']
};
for(const [locale,[name,label]] of Object.entries(localeFiles)){
  const entries=Object.entries(result[locale]).map(([key,value])=>`  ${dartString(key)}: ${dartString(value)},`).join('\n');
  const source=`// GENERATED from reference/pharmacare-preview28-fixed.html by tool/extract_i18n.js.\n// ${label}.\n// Placeholders like {n} are replaced by tf() in app_strings.dart.\n\nconst Map<String, String> ${name} = {\n${entries}\n};\n`;
  fs.writeFileSync(path.resolve(__dirname,`../lib/core/l10n/strings_${locale.toLowerCase()}.dart`),source);
}
