import 'dart:async';
import 'dart:convert';

import '../model/delta.dart';
import '../model/node.dart';
import '../model/position.dart';
import '../model/selection.dart';
import '../widget/controller.dart';
import 'operations.dart';
import 'transaction.dart';

/// JSON wire serialization for collaboration: edit transactions (and the nodes
/// they carry) round-trip through JSON so a real network transport can ferry
/// them between peers. Node **ids are preserved** (OT requires stable ids across
/// the wire).
abstract final class CollaborationWire {
  /// Encodes a transaction to a compact JSON string.
  static String encode(EditTransaction txn) => jsonEncode(transactionToJson(txn));

  /// Decodes a transaction from [json].
  static EditTransaction decode(String json) =>
      transactionFromJson(jsonDecode(json) as Map<String, Object?>);

  // ── Transactions ────────────────────────────────────────────────────────

  static Map<String, Object?> transactionToJson(EditTransaction txn) => {
        'ops': [for (final op in txn.operations) operationToJson(op)],
        if (txn.selectionBefore != null)
          'selBefore': selectionToJson(txn.selectionBefore!),
        if (txn.selectionAfter != null)
          'selAfter': selectionToJson(txn.selectionAfter!),
        if (txn.tag != null) 'tag': txn.tag,
      };

  static EditTransaction transactionFromJson(Map<String, Object?> j) =>
      EditTransaction(
        operations: [
          for (final o in j['ops'] as List)
            operationFromJson((o as Map).cast<String, Object?>())
        ],
        selectionBefore: j['selBefore'] == null
            ? null
            : selectionFromJson((j['selBefore'] as Map).cast<String, Object?>()),
        selectionAfter: j['selAfter'] == null
            ? null
            : selectionFromJson((j['selAfter'] as Map).cast<String, Object?>()),
        tag: j['tag'] as String?,
      );

  // ── Operations ──────────────────────────────────────────────────────────

  static Map<String, Object?> operationToJson(Operation op) => switch (op) {
        InsertNodeOp(:final index, :final node) =>
          {'op': 'insert', 'index': index, 'node': nodeToJson(node)},
        DeleteNodeOp(:final index, :final node) =>
          {'op': 'delete', 'index': index, 'node': nodeToJson(node)},
        ReplaceNodeOp(:final index, :final before, :final after) => {
            'op': 'replace',
            'index': index,
            'before': nodeToJson(before),
            'after': nodeToJson(after),
          },
      };

  static Operation operationFromJson(Map<String, Object?> j) {
    final index = j['index'] as int;
    Node n(String key) => nodeFromJson((j[key] as Map).cast<String, Object?>());
    switch (j['op']) {
      case 'insert':
        return InsertNodeOp(index, n('node'));
      case 'delete':
        return DeleteNodeOp(index, n('node'));
      case 'replace':
        return ReplaceNodeOp(index, n('before'), n('after'));
      default:
        throw ArgumentError('unknown op ${j['op']}');
    }
  }

  // ── Selection / position ────────────────────────────────────────────────

  static Map<String, Object?> selectionToJson(DocumentSelection s) =>
      {'base': positionToJson(s.base), 'extent': positionToJson(s.extent)};

  static DocumentSelection selectionFromJson(Map<String, Object?> j) =>
      DocumentSelection(
        base: positionFromJson((j['base'] as Map).cast<String, Object?>()),
        extent: positionFromJson((j['extent'] as Map).cast<String, Object?>()),
      );

  static Map<String, Object?> positionToJson(DocumentPosition p) {
    final np = p.nodePosition;
    return {
      'id': p.nodeId,
      if (np is TextNodePosition) 'o': np.offset,
      if (np is TableCellPosition) ...{
        'r': np.row,
        'c': np.col,
        'o': np.offset,
      },
      if (np is AtomicNodePosition) 'atomic': np.upstream,
    };
  }

  static DocumentPosition positionFromJson(Map<String, Object?> j) {
    final id = j['id'] as String;
    if (j.containsKey('r')) {
      return DocumentPosition(
          nodeId: id,
          nodePosition:
              TableCellPosition(j['r'] as int, j['c'] as int, j['o'] as int));
    }
    if (j.containsKey('atomic')) {
      return DocumentPosition(
          nodeId: id,
          nodePosition: (j['atomic'] as bool)
              ? const AtomicNodePosition.upstream()
              : const AtomicNodePosition.downstream());
    }
    return DocumentPosition.text(id, j['o'] as int? ?? 0);
  }

  // ── Nodes ───────────────────────────────────────────────────────────────

  static Map<String, Object?> nodeToJson(Node node) {
    final base = {'id': node.id, 'attrs': node.attributes};
    return switch (node) {
      TextBlockNode(:final type, :final delta) => {
          ...base,
          'k': 'text',
          'type': type,
          'delta': delta.toJson(),
        },
      CodeBlockNode(:final code, :final language) =>
        {...base, 'k': 'code', 'code': code, 'lang': language},
      HtmlBlockNode(:final html) => {...base, 'k': 'html', 'html': html},
      ImageNode(:final url, :final alt, :final title) =>
        {...base, 'k': 'image', 'url': url, 'alt': alt, 'title': title},
      MathBlockNode(:final tex) => {...base, 'k': 'math', 'tex': tex},
      MermaidNode(:final source) => {...base, 'k': 'mermaid', 'src': source},
      FrontMatterNode(:final yaml) => {...base, 'k': 'front', 'yaml': yaml},
      HorizontalRuleNode() => {...base, 'k': 'hr'},
      CustomBlockNode(:final blockType, :final data) =>
        {...base, 'k': 'custom', 'type': blockType, 'data': data},
      TableNode(:final rows, :final alignments) => {
          ...base,
          'k': 'table',
          'rows': [
            for (final row in rows) [for (final cell in row) cell.toJson()]
          ],
          'align': [for (final a in alignments) a.name],
        },
    };
  }

  static Node nodeFromJson(Map<String, Object?> j) {
    final id = j['id'] as String;
    final attrs = (j['attrs'] as Map?)?.cast<String, Object?>();
    Delta delta(Object? v) =>
        v == null ? Delta.empty() : Delta.fromJson(v as List);
    switch (j['k']) {
      case 'text':
        return TextBlockNode(
            id: id,
            type: j['type'] as String,
            delta: delta(j['delta']),
            attributes: attrs);
      case 'code':
        return CodeBlockNode(
            id: id,
            code: j['code'] as String,
            language: j['lang'] as String?,
            attributes: attrs);
      case 'html':
        return HtmlBlockNode(id: id, html: j['html'] as String);
      case 'image':
        return ImageNode(
            id: id,
            url: j['url'] as String,
            alt: j['alt'] as String?,
            title: j['title'] as String?,
            attributes: attrs);
      case 'math':
        return MathBlockNode(id: id, tex: j['tex'] as String);
      case 'mermaid':
        return MermaidNode(id: id, source: j['src'] as String);
      case 'front':
        return FrontMatterNode(id: id, yaml: j['yaml'] as String);
      case 'hr':
        return HorizontalRuleNode(id: id, attributes: attrs);
      case 'custom':
        return CustomBlockNode(
            id: id,
            blockType: j['type'] as String,
            data: (j['data'] as Map).cast<String, Object?>(),
            attributes: attrs);
      case 'table':
        return TableNode(
          id: id,
          rows: [
            for (final row in j['rows'] as List)
              [for (final cell in row as List) Delta.fromJson(cell as List)]
          ],
          alignments: [
            for (final a in j['align'] as List)
              TableAlign.values.firstWhere((e) => e.name == a)
          ],
          attributes: attrs,
        );
      default:
        throw ArgumentError('unknown node kind ${j['k']}');
    }
  }
}

/// A bidirectional message transport between two collaboration peers (serialized
/// strings — JSON over a socket, a data channel, etc.).
abstract class CollaborationTransport {
  /// Sends an encoded transaction to the remote peer(s).
  void send(String message);

  /// Encoded transactions arriving from remote peer(s).
  Stream<String> get incoming;
}

/// Two in-memory transports wired so each receives what the other sends — a
/// loopback for tests and same-process peers.
class LoopbackTransportPair {
  LoopbackTransportPair() {
    a = _LoopbackTransport(_aIn.stream, _bIn);
    b = _LoopbackTransport(_bIn.stream, _aIn);
  }

  final _aIn = StreamController<String>.broadcast(sync: true);
  final _bIn = StreamController<String>.broadcast(sync: true);
  late final CollaborationTransport a;
  late final CollaborationTransport b;

  void dispose() {
    _aIn.close();
    _bIn.close();
  }
}

class _LoopbackTransport implements CollaborationTransport {
  _LoopbackTransport(this.incoming, this._out);
  @override
  final Stream<String> incoming;
  final StreamController<String> _out;
  @override
  void send(String message) => _out.add(message);
}

/// Connects one [MarkdownEditorController] to a [CollaborationTransport]:
/// local edits are serialized and sent; incoming edits are decoded and applied.
/// (Turn-taking sync over the wire; pair with [OtCollaborationSession]-style
/// buffering for concurrent convergence.)
class TransportCollaborationSession {
  TransportCollaborationSession(this.controller, this.transport) {
    _outSub = controller.outgoing.listen((txn) {
      if (!_applyingRemote) transport.send(CollaborationWire.encode(txn));
    });
    _inSub = transport.incoming.listen((msg) {
      _applyingRemote = true;
      controller.applyRemote(CollaborationWire.decode(msg));
      _applyingRemote = false;
    });
  }

  final MarkdownEditorController controller;
  final CollaborationTransport transport;
  late final StreamSubscription<EditTransaction> _outSub;
  late final StreamSubscription<String> _inSub;
  bool _applyingRemote = false;

  void dispose() {
    _outSub.cancel();
    _inSub.cancel();
  }
}
