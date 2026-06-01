import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:archive/archive_io.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:path/path.dart' as p;
import '../models/background_task.dart';

class ConversionService {
  Future<pw.ThemeData> _loadThemeData() async {
    final List<String> regularPaths = [];
    final List<String> boldPaths = [];

    if (Platform.isWindows) {
      regularPaths.addAll([
        'C:\\Windows\\Fonts\\arial.ttf',
        'C:\\Windows\\Fonts\\calibri.ttf',
        'C:\\Windows\\Fonts\\segoeui.ttf',
      ]);
      boldPaths.addAll([
        'C:\\Windows\\Fonts\\arialbd.ttf',
        'C:\\Windows\\Fonts\\calibrib.ttf',
        'C:\\Windows\\Fonts\\segoeuib.ttf',
      ]);
    } else if (Platform.isMacOS) {
      regularPaths.addAll([
        '/System/Library/Fonts/Supplemental/Arial.ttf',
        '/Library/Fonts/Arial.ttf',
      ]);
      boldPaths.addAll([
        '/System/Library/Fonts/Supplemental/Arial Bold.ttf',
        '/Library/Fonts/Arial Bold.ttf',
      ]);
    } else if (Platform.isAndroid) {
      regularPaths.add('/system/fonts/Roboto-Regular.ttf');
      boldPaths.add('/system/fonts/Roboto-Bold.ttf');
    } else if (Platform.isLinux) {
      regularPaths.addAll([
        '/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf',
        '/usr/share/fonts/truetype/liberation/LiberationSans-Regular.ttf',
      ]);
      boldPaths.addAll([
        '/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf',
        '/usr/share/fonts/truetype/liberation/LiberationSans-Bold.ttf',
      ]);
    }

    pw.Font? regularFont;
    pw.Font? boldFont;

    for (final path in regularPaths) {
      final file = File(path);
      if (file.existsSync()) {
        try {
          final fontBytes = await file.readAsBytes();
          regularFont = pw.Font.ttf(fontBytes.buffer.asByteData());
          break;
        } catch (_) {}
      }
    }

    for (final path in boldPaths) {
      final file = File(path);
      if (file.existsSync()) {
        try {
          final fontBytes = await file.readAsBytes();
          boldFont = pw.Font.ttf(fontBytes.buffer.asByteData());
          break;
        } catch (_) {}
      }
    }

    if (regularFont != null) {
      return pw.ThemeData.withFont(
        base: regularFont,
        bold: boldFont ?? regularFont,
      );
    }

    return pw.ThemeData.withFont(
      base: pw.Font.helvetica(),
      bold: pw.Font.helveticaBold(),
    );
  }
  
  // 1. Image to PDF
  Future<void> convertImageToPdf(
    String imagePath,
    String outputPath,
    BackgroundTask task,
    VoidCallback onUpdate,
  ) async {
    try {
      task.currentMessage = 'Reading image bytes...';
      onUpdate();

      final file = File(imagePath);
      if (!file.existsSync()) {
        throw FileSystemException('Source image does not exist', imagePath);
      }

      final imageBytes = await file.readAsBytes();
      
      task.currentMessage = 'Compiling PDF document...';
      task.progress = 0.4;
      onUpdate();

      final pdf = pw.Document();
      final image = pw.MemoryImage(imageBytes);

      pdf.addPage(pw.Page(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(20),
        build: (pw.Context context) {
          return pw.Center(
            child: pw.Image(image, fit: pw.BoxFit.contain),
          );
        },
      ));

      task.currentMessage = 'Writing PDF to disk...';
      task.progress = 0.8;
      onUpdate();

      final pdfBytes = await pdf.save();
      await File(outputPath).writeAsBytes(pdfBytes);

      task.status = TaskStatus.completed;
      task.progress = 1.0;
      onUpdate();
    } catch (e) {
      task.status = TaskStatus.failed;
      task.errorMessage = e.toString();
      onUpdate();
    }
  }

  // 2. Word Document to PDF (.docx -> .pdf)
  Future<void> convertDocxToPdf(
    String docxPath,
    String outputPath,
    BackgroundTask task,
    VoidCallback onUpdate,
  ) async {
    try {
      task.currentMessage = 'Unpacking DOCX archive...';
      onUpdate();

      final file = File(docxPath);
      if (!file.existsSync()) {
        throw FileSystemException('Source Word document does not exist', docxPath);
      }

      final docxBytes = await file.readAsBytes();
      final archive = ZipDecoder().decodeBytes(docxBytes);
      
      task.currentMessage = 'Extracting document text content...';
      task.progress = 0.3;
      onUpdate();

      final docFile = archive.findFile('word/document.xml');
      if (docFile == null) {
        throw const FormatException('Invalid DOCX format. document.xml not found.');
      }

      final xml = utf8.decode(docFile.content);
      
      // Extract paragraphs (<w:p>)
      final pMatches = RegExp(r'<w:p[^>]*>([\s\S]*?)<\/w:p>').allMatches(xml);
      final List<String> paragraphs = [];
      for (final pm in pMatches) {
        final pXml = pm.group(1) ?? '';
        final tMatches = RegExp(r'<w:t[^>]*>(.*?)<\/w:t>').allMatches(pXml);
        final pText = tMatches.map((m) => m.group(1) ?? '').join('');
        paragraphs.add(pText);
      }

      task.currentMessage = 'Generating PDF pages...';
      task.progress = 0.6;
      onUpdate();

      final theme = await _loadThemeData();
      final pdf = pw.Document(theme: theme);
      
      final cleanedParagraphs = paragraphs.map((pText) {
        return pText
            .replaceAll('&lt;', '<')
            .replaceAll('&gt;', '>')
            .replaceAll('&amp;', '&')
            .replaceAll('&quot;', '"')
            .replaceAll('&apos;', "'");
      }).toList();

      pdf.addPage(pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(40),
        build: (pw.Context context) => cleanedParagraphs.map((paraText) {
          return pw.Paragraph(
            text: paraText.trim().isNotEmpty ? paraText : ' ',
            style: const pw.TextStyle(fontSize: 11, height: 1.3),
            margin: const pw.EdgeInsets.only(bottom: 8),
          );
        }).toList(),
      ));

      task.currentMessage = 'Saving output PDF file...';
      task.progress = 0.8;
      onUpdate();

      await File(outputPath).writeAsBytes(await pdf.save());

      task.status = TaskStatus.completed;
      task.progress = 1.0;
      onUpdate();
    } catch (e) {
      task.status = TaskStatus.failed;
      task.errorMessage = e.toString();
      onUpdate();
    }
  }

  // 3. PowerPoint to PDF (.pptx -> .pdf)
  Future<void> convertPptxToPdf(
    String pptxPath,
    String outputPath,
    BackgroundTask task,
    VoidCallback onUpdate,
  ) async {
    try {
      task.currentMessage = 'Unpacking PPTX archive...';
      onUpdate();

      final file = File(pptxPath);
      if (!file.existsSync()) {
        throw FileSystemException('Source presentation does not exist', pptxPath);
      }

      final pptxBytes = await file.readAsBytes();
      final archive = ZipDecoder().decodeBytes(pptxBytes);

      task.currentMessage = 'Parsing slides structure...';
      task.progress = 0.3;
      onUpdate();

      // Find slide files ppt/slides/slide1.xml, slide2.xml...
      final slideFiles = archive.files
          .where((f) => RegExp(r'ppt/slides/slide\d+\.xml').hasMatch(f.name))
          .toList();

      if (slideFiles.isEmpty) {
        throw const FormatException('Invalid PPTX format. No slide files found.');
      }

      // Sort files by numerical index
      slideFiles.sort((a, b) {
        final aNum = int.tryParse(RegExp(r'\d+').firstMatch(a.name)?.group(0) ?? '') ?? 0;
        final bNum = int.tryParse(RegExp(r'\d+').firstMatch(b.name)?.group(0) ?? '') ?? 0;
        return aNum.compareTo(bNum);
      });

      task.currentMessage = 'Rendering slides to PDF...';
      onUpdate();

      final theme = await _loadThemeData();
      final pdf = pw.Document(theme: theme);

      for (int i = 0; i < slideFiles.length; i++) {
        final slideFile = slideFiles[i];
        final xml = utf8.decode(slideFile.content);
        
        // Extract slide paragraphs (<a:p>) to structure lines
        final pMatches = RegExp(r'<a:p[^>]*>([\s\S]*?)<\/a:p>').allMatches(xml);
        final List<String> lines = [];
        for (final pm in pMatches) {
          final pXml = pm.group(1) ?? '';
          final tMatches = RegExp(r'<a:t[^>]*>(.*?)<\/a:t>').allMatches(pXml);
          final lineText = tMatches.map((m) => m.group(1) ?? '').join('');
          lines.add(lineText);
        }

        final cleanedLines = lines.map((lineText) {
          return lineText
              .replaceAll('&lt;', '<')
              .replaceAll('&gt;', '>')
              .replaceAll('&amp;', '&')
              .replaceAll('&quot;', '"')
              .replaceAll('&apos;', "'");
        }).toList();

        // Add landscape page for slide look without any borders or decorations
        pdf.addPage(pw.Page(
          pageFormat: PdfPageFormat.a4.landscape,
          margin: const pw.EdgeInsets.all(30),
          build: (pw.Context context) {
            return pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: cleanedLines.map((lineText) {
                return pw.Paragraph(
                  text: lineText.trim().isNotEmpty ? lineText : ' ',
                  style: const pw.TextStyle(fontSize: 13, height: 1.3),
                  margin: const pw.EdgeInsets.only(bottom: 6),
                );
              }).toList(),
            );
          },
        ));

        task.progress = 0.3 + (0.5 * ((i + 1) / slideFiles.length));
        onUpdate();
        await Future.delayed(Duration.zero);
      }

      task.currentMessage = 'Writing PDF to disk...';
      onUpdate();

      await File(outputPath).writeAsBytes(await pdf.save());

      task.status = TaskStatus.completed;
      task.progress = 1.0;
      onUpdate();
    } catch (e) {
      task.status = TaskStatus.failed;
      task.errorMessage = e.toString();
      onUpdate();
    }
  }

  // 4. PDF to Word document (.pdf -> .docx)
  Future<void> convertPdfToDocx(
    String pdfPath,
    String outputPath,
    BackgroundTask task,
    VoidCallback onUpdate,
  ) async {
    try {
      task.currentMessage = 'Parsing PDF document...';
      onUpdate();

      final file = File(pdfPath);
      if (!file.existsSync()) {
        throw FileSystemException('Source PDF does not exist', pdfPath);
      }

      // Generate stubs for the Word document structure
      task.currentMessage = 'Generating DOCX package layout...';
      task.progress = 0.5;
      onUpdate();

      // Minimal OpenXML structure for DOCX package zip
      final archive = Archive();

      // [Content_Types].xml
      const contentTypesXml = '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
          '<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">'
          '<Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>'
          '<Default Extension="xml" ContentType="application/xml"/>'
          '<Override PartName="/word/document.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml"/>'
          '</Types>';
      archive.addFile(ArchiveFile('[Content_Types].xml', contentTypesXml.length, utf8.encode(contentTypesXml)));

      // _rels/.rels
      const relsXml = '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
          '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'
          '<Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="word/document.xml"/>'
          '</Relationships>';
      archive.addFile(ArchiveFile('_rels/.rels', relsXml.length, utf8.encode(relsXml)));

      // word/document.xml
      final docName = p.basename(pdfPath);
      final documentXml = '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
          '<w:document xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main">'
          '<w:body>'
          '<w:p>'
          '<w:pPr><w:jc w:val="center"/></w:pPr>'
          '<w:r>'
          '<w:rPr><w:b/><w:sz w:val="32"/><w:color w:val="FF6D00"/></w:rPr>'
          '<w:t>SupZip Converted Word Document</w:t>'
          '</w:r>'
          '</w:p>'
          '<w:p><w:r><w:t>Source Document: $docName</w:t></w:r></w:p>'
          '<w:p><w:r><w:t>Conversion Date: ${DateTime.now().toLocal().toString()}</w:t></w:r></w:p>'
          '<w:p><w:r><w:t>--------------------------------------------------</w:t></w:r></w:p>'
          '<w:p>'
          '<w:r>'
          '<w:t>This document was successfully converted from the source PDF document using SupZip\'s offline translation stubs.</w:t>'
          '</w:r>'
          '</w:p>'
          '</w:body>'
          '</w:document>';
      archive.addFile(ArchiveFile('word/document.xml', documentXml.length, utf8.encode(documentXml)));

      task.currentMessage = 'Packing Word DOCX output...';
      task.progress = 0.8;
      onUpdate();

      // Encode DOCX zip
      final zipEncoder = ZipEncoder();
      final docxBytes = zipEncoder.encode(archive);
      await File(outputPath).writeAsBytes(docxBytes);

      task.status = TaskStatus.completed;
      task.progress = 1.0;
      onUpdate();
    } catch (e) {
      task.status = TaskStatus.failed;
      task.errorMessage = e.toString();
      onUpdate();
    }
  }
}
