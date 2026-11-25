import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:season_planner/core/data/models/role_document_model.dart';
import 'package:season_planner/core/services/role_document_service.dart';
import 'package:season_planner/core/widgets/markdown_document_view.dart';
import 'package:season_planner/fsAdmin/flight_school_provider.dart';

class ManageRoleDocumentsView extends StatefulWidget {
  final int initialTab;

  const ManageRoleDocumentsView({super.key, this.initialTab = 0});

  @override
  State<ManageRoleDocumentsView> createState() =>
      _ManageRoleDocumentsViewState();
}

class _ManageRoleDocumentsViewState extends State<ManageRoleDocumentsView> {
  final _service = RoleDocumentService();
  List<RoleDocument> _docs = [];
  bool _loading = true;
  bool _busy = false;

  static const _checklistTemplate = '''# Checkliste

## Vorbereitung
- [ ] Ausrüstung vollständig geprüft und einsatzbereit
- [ ] Akkus geladen & Ersatzmaterial eingepackt

## Durchführung
- [ ] Einweisung / Briefing durchgeführt

## Nachbereitung
- [ ] Material gereinigt, geprüft und vollständig zurückgegeben
- [ ] Besondere Vorkommnisse dokumentiert
''';

  static const _instructionTemplate = '''# Arbeitsanweisung

## Ziel & Überblick
Kurze Beschreibung der Aufgabe für diese Position.

## Ablauf
1. Erster Schritt
2. Zweiter Schritt

> **Wichtiger Hinweis:** Sicherheitsrelevante Details hier hervorheben.
''';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final fs = context.read<FlightSchoolProvider>().flightSchool;
    if (fs == null) return;
    setState(() => _loading = true);
    final list = await _service.listSchoolDocuments(fs.id);
    if (!mounted) return;
    setState(() {
      _docs = list;
      _loading = false;
    });
  }

  String _fmtDate(DateTime? d) {
    if (d == null) return '—';
    return '${d.day.toString().padLeft(2, '0')}.${d.month.toString().padLeft(2, '0')}.${d.year}';
  }

  Future<void> _openEditorDialog({
    required RoleDocumentType docType,
    RoleDocument? existing,
  }) async {
    final fs = context.read<FlightSchoolProvider>().flightSchool;
    if (fs == null) return;

    final titleCtrl = TextEditingController(text: existing?.title ?? '');
    final contentCtrl = TextEditingController(text: existing?.contentMd ?? '');
    List<String>? importedAssetFileIds;
    String? importInfo;
    String? importWarning;
    String? validationError;
    bool importing = false;

    final ok = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setLocal) {
            final cs = Theme.of(ctx).colorScheme;
            final isChecklist = docType == RoleDocumentType.checklist;
            final parsedPreviewCount = isChecklist
                ? parseChecklistMarkdown(contentCtrl.text).length
                : 0;

            return AlertDialog(
              title: Text(
                existing == null
                    ? (isChecklist
                        ? 'Neue Checkliste hinzufügen'
                        : 'Neue Arbeitsanweisung hinzufügen')
                    : '${docType.label} bearbeiten (v${existing.version})',
              ),
              content: SizedBox(
                width: 580,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // Import-Box (.md, .md + Bilder, .zip)
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: cs.primaryContainer.withValues(alpha: 0.35),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: cs.primary.withValues(alpha: 0.25),
                          ),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              isChecklist
                                  ? 'Markdown-Checkliste (.md) importieren'
                                  : 'Markdown-Datei (.md), .md + Bilder oder .zip importieren',
                              style: const TextStyle(
                                fontWeight: FontWeight.w700,
                                fontSize: 13.5,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              isChecklist
                                  ? 'Aufgaben einfach mit „- [ ] Aufgabe“ und Abschnitte mit „## Abschnitt“ in Markdown schreiben.'
                                  : 'Lokale Bilder aus deinem Markdown (z. B. ![Bild](images/foto.jpg)) werden automatisch hochgeladen & verknüpft, wenn du eine .zip oder die .md + Bilddateien gemeinsam auswählst.',
                              style: TextStyle(
                                fontSize: 12,
                                color: cs.onSurfaceVariant,
                              ),
                            ),
                            const SizedBox(height: 10),
                            Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              children: [
                                FilledButton.tonalIcon(
                                  onPressed: importing
                                      ? null
                                      : () async {
                                          final res = await FilePicker.platform
                                              .pickFiles(
                                            allowMultiple: true,
                                            withData: true,
                                            type: FileType.custom,
                                            allowedExtensions: [
                                              'md',
                                              'markdown',
                                              'zip',
                                              'png',
                                              'jpg',
                                              'jpeg',
                                              'webp',
                                              'gif',
                                              'svg',
                                            ],
                                          );
                                          if (res == null ||
                                              res.files.isEmpty) {
                                            return;
                                          }
                                          setLocal(() {
                                            importing = true;
                                            validationError = null;
                                            importInfo = null;
                                            importWarning = null;
                                          });
                                          try {
                                            final files = res.files
                                                .where((f) => f.bytes != null)
                                                .map((f) => (
                                                      name: f.name,
                                                      bytes: f.bytes!,
                                                    ))
                                                .toList();
                                            final imported = await _service
                                                .importMarkdownBundle(
                                              pickedFiles: files,
                                            );
                                            setLocal(() {
                                              if (titleCtrl.text
                                                  .trim()
                                                  .isEmpty) {
                                                titleCtrl.text =
                                                    imported.suggestedTitle;
                                              }
                                              contentCtrl.text =
                                                  imported.processedMd;
                                              importedAssetFileIds =
                                                  imported.assetFileIds;
                                              importInfo = imported
                                                          .uploadedImageCount >
                                                      0
                                                  ? 'Markdown importiert · ${imported.uploadedImageCount} Bild${imported.uploadedImageCount == 1 ? "" : "er"} automatisch hochgeladen & verknüpft.'
                                                  : 'Markdown erfolgreich importiert.';
                                              if (imported
                                                  .missingImageRefs.isNotEmpty) {
                                                importWarning =
                                                    'Folgende lokale Bildpfade waren nicht im Upload enthalten und konnten nicht verknüpft werden: ${imported.missingImageRefs.join(', ')}.\nTipp: Lade die .md zusammen mit den Bildern (oder als .zip) hoch.';
                                              }
                                            });
                                          } catch (e) {
                                            setLocal(() {
                                              validationError =
                                                  'Import fehlgeschlagen: $e';
                                            });
                                          } finally {
                                            setLocal(() => importing = false);
                                          }
                                        },
                                  icon: importing
                                      ? const SizedBox(
                                          width: 16,
                                          height: 16,
                                          child: CircularProgressIndicator(
                                            strokeWidth: 2,
                                          ),
                                        )
                                      : const Icon(Icons.upload_file, size: 18),
                                  label: Text(
                                    importing
                                        ? 'Importiere...'
                                        : 'Datei(en) / .zip auswählen',
                                  ),
                                ),
                                OutlinedButton.icon(
                                  onPressed: importing
                                      ? null
                                      : () {
                                          setLocal(() {
                                            contentCtrl.text = isChecklist
                                                ? _checklistTemplate
                                                : _instructionTemplate;
                                            validationError = null;
                                          });
                                        },
                                  icon: const Icon(Icons.description_outlined,
                                      size: 18),
                                  label: const Text('Beispiel einfügen'),
                                ),
                              ],
                            ),
                            if (importInfo != null) ...[
                              const SizedBox(height: 8),
                              Row(
                                children: [
                                  Icon(Icons.check_circle,
                                      size: 16, color: Colors.green.shade700),
                                  const SizedBox(width: 6),
                                  Expanded(
                                    child: Text(
                                      importInfo!,
                                      style: TextStyle(
                                        fontSize: 12,
                                        fontWeight: FontWeight.w600,
                                        color: Colors.green.shade700,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ],
                            if (importWarning != null) ...[
                              const SizedBox(height: 8),
                              Container(
                                padding: const EdgeInsets.all(8),
                                decoration: BoxDecoration(
                                  color: Colors.orange.withValues(alpha: 0.14),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Text(
                                  importWarning!,
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: Colors.orange.shade900,
                                  ),
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: titleCtrl,
                        onChanged: (_) {
                          if (validationError != null) {
                            setLocal(() => validationError = null);
                          }
                        },
                        decoration: InputDecoration(
                          labelText: 'Titel *',
                          hintText: isChecklist
                              ? 'z. B. Checkliste Kamera-Crew'
                              : 'z. B. Kamera-Setup & Datensicherung',
                        ),
                      ),
                      const SizedBox(height: 10),
                      TextField(
                        controller: contentCtrl,
                        maxLines: 10,
                        onChanged: (_) => setLocal(() => validationError = null),
                        style: const TextStyle(
                          fontFamily: 'monospace',
                          fontSize: 12.5,
                        ),
                        decoration: InputDecoration(
                          labelText: 'Markdown-Inhalt *',
                          alignLabelWithHint: true,
                          helperText: isChecklist
                              ? 'Erkannte Checklisten-Punkte: $parsedPreviewCount'
                              : 'Standard-Markdown (# Überschrift, Listen, Tabellen, Bilder)',
                        ),
                      ),
                      if (validationError != null) ...[
                        const SizedBox(height: 10),
                        Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: cs.errorContainer.withValues(alpha: 0.55),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(
                              color: cs.error.withValues(alpha: 0.6),
                            ),
                          ),
                          child: Text(
                            validationError!,
                            style: TextStyle(
                              color: cs.error,
                              fontSize: 12.5,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: importing ? null : () => Navigator.pop(ctx, false),
                  child: const Text('Abbrechen'),
                ),
                FilledButton(
                  onPressed: importing
                      ? null
                      : () {
                          if (titleCtrl.text.trim().isEmpty) {
                            setLocal(() => validationError =
                                'Bitte gib einen Titel ein.');
                            return;
                          }
                          if (contentCtrl.text.trim().isEmpty) {
                            setLocal(() => validationError =
                                'Bitte importiere eine .md-Datei oder gib Markdown-Inhalt ein.');
                            return;
                          }
                          if (isChecklist &&
                              parseChecklistMarkdown(contentCtrl.text).isEmpty) {
                            setLocal(() => validationError =
                                'In der Checkliste wurden keine Aufgaben erkannt. Bitte füge Zeilen im Format „- [ ] Aufgabe“ hinzu.');
                            return;
                          }
                          Navigator.pop(ctx, true);
                        },
                  child: const Text('Speichern'),
                ),
              ],
            );
          },
        );
      },
    );

    final finalTitle = titleCtrl.text.trim();
    final finalMd = contentCtrl.text;
    titleCtrl.dispose();
    contentCtrl.dispose();

    if (ok != true) return;

    setState(() => _busy = true);
    try {
      if (existing == null) {
        await _service.createDocument(
          flightSchoolId: fs.id,
          docType: docType,
          title: finalTitle,
          contentMd: finalMd,
          assetFileIds: importedAssetFileIds ?? const [],
        );
      } else {
        await _service.updateDocument(
          existing: existing,
          title: finalTitle,
          contentMd: finalMd,
          newAssetFileIds: importedAssetFileIds,
        );
      }
      await _load();
      if (mounted) {
        ScaffoldMessenger.maybeOf(context)?.showSnackBar(
          SnackBar(content: Text('${docType.label} „$finalTitle“ gespeichert.')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.maybeOf(context)?.showSnackBar(
          SnackBar(content: Text('Speichern fehlgeschlagen: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _deleteDoc(RoleDocument doc) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('${doc.docType.label} löschen?'),
        content: Text(
          'Möchtest du „${doc.title}“ wirklich dauerhaft aus der Bibliothek löschen?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Abbrechen'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Löschen'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    setState(() => _busy = true);
    await _service.deleteDocument(doc);
    await _load();
    if (mounted) {
      setState(() => _busy = false);
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        SnackBar(content: Text('„${doc.title}“ gelöscht.')),
      );
    }
  }

  void _openPreview(RoleDocument doc) {
    if (doc.docType == RoleDocumentType.instruction) {
      Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => MarkdownDocumentView(document: doc)),
      );
      return;
    }

    // Checklisten-Vorschau mit geparsten Abschnitten & Checkboxen
    final items = doc.parseChecklistItems();
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('${doc.title} (Vorschau v${doc.version})'),
        content: SizedBox(
          width: 480,
          child: SingleChildScrollView(
            child: items.isEmpty
                ? const Text('Keine Aufgabenpunkte erkannt.')
                : Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${items.length} Aufgabenpunkte erkannt:',
                        style: const TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 13,
                        ),
                      ),
                      const SizedBox(height: 8),
                      ...items.map((it) {
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 6),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Icon(
                                Icons.check_box_outline_blank,
                                size: 18,
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  it.section.isNotEmpty
                                      ? '${it.section}: ${it.text}'
                                      : it.text,
                                  style: const TextStyle(fontSize: 13),
                                ),
                              ),
                            ],
                          ),
                        );
                      }),
                    ],
                  ),
          ),
        ),
        actions: [
          FilledButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Schließen'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final fs = context.watch<FlightSchoolProvider>().flightSchool;
    if (fs == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    final instructions = _docs
        .where((d) => d.docType == RoleDocumentType.instruction)
        .toList();
    final checklists =
        _docs.where((d) => d.docType == RoleDocumentType.checklist).toList();

    return DefaultTabController(
      length: 2,
      initialIndex: widget.initialTab,
      child: Builder(
        builder: (tabContext) {
          return Scaffold(
            appBar: AppBar(
              title: const Text('Anweisungen & Checklisten'),
              bottom: TabBar(
                tabs: [
                  Tab(
                    icon: const Icon(Icons.menu_book_outlined),
                    text: 'Arbeitsanweisungen (${instructions.length})',
                  ),
                  Tab(
                    icon: const Icon(Icons.checklist),
                    text: 'Checklisten (${checklists.length})',
                  ),
                ],
              ),
            ),
            floatingActionButton: FloatingActionButton.extended(
              onPressed: _busy
                  ? null
                  : () {
                      final idx = DefaultTabController.of(tabContext).index;
                      _openEditorDialog(
                        docType: idx == 0
                            ? RoleDocumentType.instruction
                            : RoleDocumentType.checklist,
                      );
                    },
              icon: const Icon(Icons.add),
              label: const Text('Hochladen / Neu'),
            ),
            body: SafeArea(
              child: Column(
                children: [
                  if (_busy) const LinearProgressIndicator(minHeight: 2),
                  Expanded(
                    child: _loading
                        ? const Center(child: CircularProgressIndicator())
                        : TabBarView(
                            children: [
                              _buildList(
                                items: instructions,
                                emptyText:
                                    'Noch keine Arbeitsanweisungen vorhanden.\nLade eine Markdown-Datei (.md) oder ein .zip-Paket inkl. Bildern hoch und ordne sie anschließend unter „Teamrollen verwalten“ den passenden Rollen zu.',
                                icon: Icons.menu_book_outlined,
                              ),
                              _buildList(
                                items: checklists,
                                emptyText:
                                    'Noch keine Checklisten vorhanden.\nLade eine Markdown-Checkliste (- [ ] Aufgabe) hoch und weise sie anschließend einer Teamrolle zu.',
                                icon: Icons.checklist,
                              ),
                            ],
                          ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildList({
    required List<RoleDocument> items,
    required String emptyText,
    required IconData icon,
  }) {
    if (items.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            emptyText,
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.black54),
          ),
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.separated(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 88),
        itemCount: items.length,
        separatorBuilder: (_, __) => const SizedBox(height: 8),
        itemBuilder: (context, index) {
          final doc = items[index];
          final isChecklist = doc.docType == RoleDocumentType.checklist;
          final subtitleParts = <String>[
            'v${doc.version}',
            if (isChecklist) '${doc.parseChecklistItems().length} Punkte',
            if (doc.assetFileIds.isNotEmpty)
              '${doc.assetFileIds.length} Bild${doc.assetFileIds.length == 1 ? "" : "er"}',
            'Stand: ${_fmtDate(doc.updatedAt)}',
          ];

          return Card(
            child: ListTile(
              leading: CircleAvatar(
                backgroundColor: Theme.of(context).colorScheme.primaryContainer,
                child: Icon(
                  icon,
                  color: Theme.of(context).colorScheme.primary,
                ),
              ),
              title: Text(
                doc.title,
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
              subtitle: Text(
                subtitleParts.join(' · '),
                style: const TextStyle(fontSize: 12.5),
              ),
              onTap: () => _openPreview(doc),
              trailing: PopupMenuButton<String>(
                onSelected: (v) {
                  if (v == 'preview') _openPreview(doc);
                  if (v == 'edit') {
                    _openEditorDialog(docType: doc.docType, existing: doc);
                  }
                  if (v == 'delete') _deleteDoc(doc);
                },
                itemBuilder: (_) => const [
                  PopupMenuItem(value: 'preview', child: Text('Vorschau')),
                  PopupMenuItem(
                    value: 'edit',
                    child: Text('Bearbeiten / Neue Version'),
                  ),
                  PopupMenuItem(value: 'delete', child: Text('Löschen')),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}
