// File: lib/widgets/polyrhythm_settings_modal.dart
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class PolyrhythmSettingsModal extends StatefulWidget {
  const PolyrhythmSettingsModal({super.key});
  @override
  State<PolyrhythmSettingsModal> createState() => _PolyrhythmSettingsModalState();
}

class _PolyrhythmSettingsModalState extends State<PolyrhythmSettingsModal> {
  bool tempoIncreaseEnabled = false;
  int tempoIncreaseX = 1;
  int tempoIncreaseY = 1;

  bool polyrhythmEnabled = false;
  bool polyrhythmAccented = false;
  @override
  void initState() {
    super.initState();
    _loadAll();
  }
  Future<void> _loadAll() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      tempoIncreaseEnabled = prefs.getBool('tempo_increase_enabled') ?? false;
      tempoIncreaseX = prefs.getInt('tempo_increase_x') ?? 1;
      tempoIncreaseY = prefs.getInt('tempo_increase_y') ?? 1;
      polyrhythmEnabled = prefs.getBool('polyrhythm_enabled') ?? false;
      polyrhythmAccented = prefs.getBool('polyrhythm_accented') ?? false;
    });
  }
  Future<void> _setTempoIncreaseEnabled(bool v) async {final prefs = await SharedPreferences.getInstance();await prefs.setBool('tempo_increase_enabled',v);setState(()=>tempoIncreaseEnabled=v);}  
  Future<void> _saveTempoValues() async {final prefs = await SharedPreferences.getInstance();await prefs.setInt('tempo_increase_x',tempoIncreaseX);await prefs.setInt('tempo_increase_y',tempoIncreaseY);}  
  Future<void> _setPolyrhythmEnabled(bool v) async {final prefs = await SharedPreferences.getInstance();await prefs.setBool('polyrhythm_enabled',v);setState(()=>polyrhythmEnabled=v);}  
  Future<void> _setPolyrhythmAccented(bool v) async {final prefs = await SharedPreferences.getInstance();await prefs.setBool('polyrhythm_accented',v);setState(()=>polyrhythmAccented=v);}  
  @override
  Widget build(BuildContext context) {
    final submenuStyle = Theme.of(context).textTheme.bodySmall ?? const TextStyle(fontSize:12);
    return DraggableScrollableSheet(
      expand:false,
      builder:(_,ctrl)=>SingleChildScrollView(
        controller:ctrl,
        padding:const EdgeInsets.all(16),
        child:Column(
          crossAxisAlignment:CrossAxisAlignment.start,
          children:[
            SwitchListTile(title:const Text('Tempo Increase'),value:tempoIncreaseEnabled,onChanged:_setTempoIncreaseEnabled),
            if(tempoIncreaseEnabled)Padding(padding:const EdgeInsets.symmetric(horizontal:16),child:DefaultTextStyle(style:submenuStyle,child:Row(children:[const Text('Increase bpm by'),const SizedBox(width:8),DropdownButton<int>(value:tempoIncreaseX,items:List.generate(16,(i)=>i+1).map((v)=>DropdownMenuItem(value:v,child:Text('$v'))).toList(),onChanged:(v){if(v==null)return;setState(()=>tempoIncreaseX=v);_saveTempoValues();}),const SizedBox(width:8),const Text('every'),const SizedBox(width:8),DropdownButton<int>(value:tempoIncreaseY,items:List.generate(16,(i)=>i+1).map((v)=>DropdownMenuItem(value:v,child:Text('$v'))).toList(),onChanged:(v){if(v==null)return;setState(()=>tempoIncreaseY=v);_saveTempoValues();}),const SizedBox(width:8),const Text('beats'),],),),),
            const Divider(),
            SwitchListTile(title:const Text('Polyrhythm Mode'),value:polyrhythmEnabled,onChanged:_setPolyrhythmEnabled),
            if(polyrhythmEnabled)Padding(padding:const EdgeInsets.only(left:16),child:ListTile(dense:true,contentPadding:const EdgeInsets.only(left:0),title:Text('Polyrhythm uses accented clicks',style:submenuStyle),trailing:Transform.scale(scale:0.8,child:Switch(value:polyrhythmAccented,onChanged:_setPolyrhythmAccented)),),),
          ],
        ),
      ),
    );
  }
}
