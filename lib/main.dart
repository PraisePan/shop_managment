import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

void main() => runApp(const MyApp());

// ---------- نموذج الطلب ----------
class Order {
  String id, name, phone, details;
  bool depositPaid;
  double depositAmount;
  List<String> photos; // أسماء ملفات الصور فقط
  DateTime date;

  Order({
    required this.id,
    required this.name,
    required this.phone,
    required this.details,
    required this.depositPaid,
    required this.depositAmount,
    required this.photos,
    required this.date,
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'phone': phone,
    'details': details,
    'depositPaid': depositPaid,
    'depositAmount': depositAmount,
    'photos': photos,
    'date': date.toIso8601String(),
  };

  factory Order.fromJson(Map<String, dynamic> j) => Order(
    id: j['id'],
    name: j['name'],
    phone: j['phone'],
    details: j['details'],
    depositPaid: j['depositPaid'],
    depositAmount: (j['depositAmount'] as num).toDouble(),
    photos: List<String>.from(j['photos']),
    date: DateTime.parse(j['date']),
  );
}

// ---------- التخزين المحلي ----------
class Storage {
  static Future<Directory> get dir async {
    final d = await getApplicationDocumentsDirectory();
    final p = Directory('${d.path}/photos');
    if (!await p.exists()) await p.create(recursive: true);
    return d;
  }

  static Future<List<Order>> load() async {
    final f = File('${(await dir).path}/orders.json');
    if (!await f.exists()) return [];
    final list = jsonDecode(await f.readAsString()) as List;
    return list.map((e) => Order.fromJson(e)).toList();
  }

  static Future<void> save(List<Order> orders) async {
    final f = File('${(await dir).path}/orders.json');
    await f.writeAsString(jsonEncode(orders.map((o) => o.toJson()).toList()));
  }

  // نسخ الصورة لمجلد التطبيق وإرجاع اسمها
  static Future<String> savePhoto(String sourcePath) async {
    final name = '${DateTime.now().microsecondsSinceEpoch}.jpg';
    await File(sourcePath).copy('${(await dir).path}/photos/$name');
    return name;
  }

  // تصدير كل شيء في ملف zip ومشاركته
  static Future<void> exportZip() async {
    final base = (await dir).path;
    final archive = Archive();

    final ordersFile = File('$base/orders.json');
    if (await ordersFile.exists()) {
      final b = await ordersFile.readAsBytes();
      archive.addFile(ArchiveFile('orders.json', b.length, b));
    }
    final photosDir = Directory('$base/photos');
    for (final f in photosDir.listSync().whereType<File>()) {
      final b = await f.readAsBytes();
      final n = f.path.split(Platform.pathSeparator).last;
      archive.addFile(ArchiveFile('photos/$n', b.length, b));
    }

    final zipData = ZipEncoder().encode(archive);
    final today = DateTime.now().toIso8601String().substring(0, 10);
    final out = File('$base/export_$today.zip');
    await out.writeAsBytes(zipData);
    await Share.shareXFiles([XFile(out.path)]);
  }
}

// ---------- التطبيق ----------
class MyApp extends StatelessWidget {
  const MyApp({super.key});
  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'طلبات المحل',
    theme: ThemeData(
      colorSchemeSeed: const Color.fromARGB(255, 93, 196, 214),
      useMaterial3: true,
    ),
    builder: (c, child) =>
        Directionality(textDirection: TextDirection.rtl, child: child!),
    home: const OrdersPage(),
  );
}

// ---------- قائمة الطلبات ----------
class OrdersPage extends StatefulWidget {
  const OrdersPage({super.key});
  @override
  State<OrdersPage> createState() => _OrdersPageState();
}

class _OrdersPageState extends State<OrdersPage> {
  List<Order> orders = [];

  @override
  void initState() {
    super.initState();
    _reload();
  }

  Future<void> _reload() async {
    final l = await Storage.load();
    setState(() => orders = l.reversed.toList());
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('طلبات المحل'),
      actions: [
        IconButton(
          icon: const Icon(Icons.ios_share),
          tooltip: 'تصدير',
          onPressed: Storage.exportZip,
        ),
      ],
    ),
    body: orders.isEmpty
        ? const Center(child: Text('لا توجد طلبات'))
        : ListView.builder(
            itemCount: orders.length,
            itemBuilder: (c, i) {
              final o = orders[i];
              return ListTile(
                title: Text(o.name),
                subtitle: Text('${o.phone}\n${o.details}', maxLines: 2),
                isThreeLine: true,
                trailing: Icon(
                  o.depositPaid ? Icons.check_circle : Icons.cancel,
                  color: o.depositPaid ? Colors.green : Colors.red,
                ),
              );
            },
          ),
    floatingActionButton: FloatingActionButton.extended(
      icon: const Icon(Icons.add),
      label: const Text('طلب جديد'),
      onPressed: () async {
        await Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const NewOrderPage()),
        );
        _reload();
      },
    ),
  );
}

// ---------- شاشة طلب جديد ----------
class NewOrderPage extends StatefulWidget {
  const NewOrderPage({super.key});
  @override
  State<NewOrderPage> createState() => _NewOrderPageState();
}

class _NewOrderPageState extends State<NewOrderPage> {
  final name = TextEditingController();
  final phone = TextEditingController();
  final details = TextEditingController();
  final deposit = TextEditingController();
  bool depositPaid = false;
  final List<String> photoNames = [];
  final List<String> photoPaths = [];

  Future<void> _addPhoto(ImageSource src) async {
    final x = await ImagePicker().pickImage(source: src, imageQuality: 70);
    if (x == null) return;
    final n = await Storage.savePhoto(x.path);
    setState(() {
      photoNames.add(n);
      photoPaths.add(x.path);
    });
  }

  Future<void> _save() async {
    if (name.text.trim().isEmpty) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('اكتب اسم الزبون')));
      return;
    }
    final all = await Storage.load();
    all.add(
      Order(
        id: DateTime.now().millisecondsSinceEpoch.toString(),
        name: name.text.trim(),
        phone: phone.text.trim(),
        details: details.text.trim(),
        depositPaid: depositPaid,
        depositAmount: depositPaid ? (double.tryParse(deposit.text) ?? 0) : 0,
        photos: photoNames,
        date: DateTime.now(),
      ),
    );
    await Storage.save(all);
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('طلب جديد')),
    body: ListView(
      padding: const EdgeInsets.all(16),
      children: [
        TextField(
          controller: name,
          decoration: const InputDecoration(labelText: 'اسم الزبون'),
        ),
        TextField(
          controller: phone,
          keyboardType: TextInputType.phone,
          decoration: const InputDecoration(labelText: 'رقم الجوال'),
        ),
        TextField(
          controller: details,
          maxLines: 4,
          decoration: const InputDecoration(labelText: 'تفاصيل الطلب'),
        ),
        SwitchListTile(
          title: const Text('دفع عربون؟'),
          value: depositPaid,
          onChanged: (v) => setState(() => depositPaid = v),
        ),
        if (depositPaid)
          TextField(
            controller: deposit,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(labelText: 'مبلغ العربون'),
          ),
        const SizedBox(height: 12),
        Row(
          children: [
            ElevatedButton.icon(
              onPressed: () => _addPhoto(ImageSource.camera),
              icon: const Icon(Icons.camera_alt),
              label: const Text('كاميرا'),
            ),
            const SizedBox(width: 8),
            ElevatedButton.icon(
              onPressed: () => _addPhoto(ImageSource.gallery),
              icon: const Icon(Icons.photo),
              label: const Text('معرض'),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          children: photoPaths
              .map(
                (p) => Image.file(
                  File(p),
                  width: 90,
                  height: 90,
                  fit: BoxFit.cover,
                ),
              )
              .toList(),
        ),
        const SizedBox(height: 20),
        FilledButton(onPressed: _save, child: const Text('حفظ الطلب')),
      ],
    ),
  );
}
