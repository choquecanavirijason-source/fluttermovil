import 'dart:convert';
import 'dart:io';
import '../../lib/lashes/cat_eye_recipe.dart';
void main() {
 const names=['Cat Eye','Wispy','Cat Classic','Foxy Eye','Natural','Doll Eye','Squirrel','Kitten','Wet Look','Anime','Kim K'];
 final templates=<String,dynamic>{};
 final styles=<Map<String,dynamic>>[];
 for(var i=0;i<names.length;i++) {
  final r=CatEyeRecipe(style:i);
  final baseFactor=i==9 ? 1.9/.82 : 1.0;
  final profile={
   'length_profile':List.generate(17,(j)=>{'t':j/16,'length':double.parse((r.lengthAt(j/16,0)/baseFactor).toStringAsFixed(6))}),
   'curl':r.curl,'fan':r.fan,'sweep':r.sweep,
   'roots':List.generate(4,(t)=>CatEyeRecipe(style:i,technique:t).roots),
   'spike_every':i==1?4:i==9||i==8?2:i==10?5:0,
   'spike_offset':i==1||i==10?2:i==8?1:0,
   'spike_multiplier':i==1?1.42/.92:i==9?1.9/.82:i==10?1.6/.94:i==8 ? .93/1.03:1.0,
   'fan_spread':i==8?1.6:i==9?5.0:10.0,'mega_fan_spread':i==8?1.6:i==9?5.0:16.0,
   'width_multiplier':1.0,
  };
  templates[r.styleId]=profile;
  styles.add({'key':r.styleId,'name':names[i],'description':'','thumbnail':null,'builtin_style':r.styleId,'profile':null,'is_active':true,'sort_order':i,'allowed_lengths':[0,1,2],'allowed_techniques':[0,1,2,3],'allowed_thicknesses':[0,1,2,3],'defaults':{'length':1,'technique':0,'thickness':3},'eye_types':[]});
 }
 final file=File('build/tryon_integration/defaults.json');file.parent.createSync(recursive:true);
 file.writeAsStringSync(const JsonEncoder.withIndent('  ').convert({'schema_version':1,'engine_version':1,'styles':styles,'templates':templates}));
}
