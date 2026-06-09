/// markey_mark — a from-scratch, fully native, cross-platform WYSIWYG Markdown
/// editor for Flutter. Google-Docs feel, Markdown as the source of truth,
/// switchable WYSIWYG/source modes. No WebView, no JavaScript — 100% native.
///
/// See `specs/design/` in the repository for the full design specification.
library;

// Model (L1)
export 'src/model/attributes.dart' show Attributes, InlineAttr;
export 'src/model/delta.dart' show Delta, TextRun;
export 'src/model/node.dart'
    show
        Node,
        TextBlockNode,
        CodeBlockNode,
        HtmlBlockNode,
        HorizontalRuleNode,
        ImageNode,
        MathBlockNode,
        TableNode,
        TableAlign,
        MermaidNode,
        FrontMatterNode,
        CustomBlockNode,
        BlockType,
        NodeIds,
        NodeIdGenerator;
export 'src/model/document.dart' show Document;
export 'src/model/document_text.dart' show DocumentText;
export 'src/model/position.dart'
    show
        DocumentPosition,
        NodePosition,
        TextNodePosition,
        AtomicNodePosition,
        TableCellPosition;
export 'src/model/selection.dart' show DocumentSelection;

// Editing (L4)
export 'src/editing/operations.dart'
    show Operation, InsertNodeOp, DeleteNodeOp, ReplaceNodeOp;
export 'src/editing/transaction.dart' show EditTransaction;
export 'src/editing/editor.dart' show Editor;
export 'src/editing/commands.dart' show EditCommands;
export 'src/editing/caret_motor.dart' show CaretMotor, CaretGranularity;
export 'src/editing/ot_session.dart' show OtCollaborationSession;
export 'src/editing/wire.dart'
    show
        CollaborationWire,
        CollaborationTransport,
        LoopbackTransportPair,
        TransportCollaborationSession;
export 'src/model/fractional_index.dart' show FractionalIndex;
export 'src/editing/input_rules.dart'
    show
        InputRule,
        HeadingInputRule,
        WrapInputRule,
        BlockPrefixInputRule,
        HorizontalRuleInputRule,
        LinkifyInputRule,
        defaultInputRules,
        applyInputRules;
export 'src/editing/search.dart' show MatchLocation, findInDocument;
export 'src/editing/collaboration.dart' show CollaborationSession;
export 'src/editing/ot.dart' show transformOperation, transformTransaction;

// Markdown pipeline (L0)
export 'src/markdown/decoder.dart' show MarkdownDecoder;
export 'src/markdown/encoder.dart' show MarkdownEncoder;
export 'src/markdown/markdown.dart' show Markdown, MarkdownToHtml;
export 'src/markdown/block_codecs.dart' show CustomBlockCodec, BlockCodecs;
export 'src/markdown/html_encoder.dart' show HtmlEncoder;
export 'src/export/pdf_export.dart' show PdfExporter;
export 'src/markdown/slug.dart' show slugify, SlugAllocator;

// Widget + controller (L7)
export 'src/widget/controller.dart'
    show MarkdownEditorController, EditorMode, DocumentStats, OutlineEntry;
export 'src/widget/clipboard.dart'
    show
        ClipboardPayload,
        ClipboardBridge,
        SystemClipboardBridge,
        SuperClipboardBridge;
export 'src/widget/drop.dart' show DroppedItem, DropKind;
export 'src/widget/markdown_editor.dart' show MarkdownEditor;
export 'src/widget/labels.dart' show MarkdownEditorLabels;
export 'src/widget/block_registry.dart' show BlockRegistry, BlockBuilder;
export 'src/render/delta_text.dart' show deltaToTextSpan;
export 'src/render/code_highlight.dart'
    show CodeHighlighter, DefaultCodeHighlighter;
export 'src/render/markdown_source_highlight.dart'
    show markdownSourceSpans, MarkdownSourceTheme;
export 'src/theme/editor_style.dart' show EditorStyle;
export 'src/ui/slash_menu.dart' show SlashMenu, SlashMenuItem, defaultSlashItems;
export 'src/render/diagram_renderer.dart'
    show DiagramRenderer, SourceCardDiagramRenderer, NativeDiagramRenderer;
export 'src/diagram/mermaid_pie.dart'
    show PieChart, PieSlice, parsePie, MermaidPieView;
export 'src/diagram/mermaid_journey.dart'
    show
        Journey,
        JourneySection,
        JourneyTask,
        parseJourney,
        MermaidJourneyView;
export 'src/diagram/mermaid_timeline.dart'
    show
        Timeline,
        TimelineSection,
        TimelinePeriod,
        parseTimeline,
        MermaidTimelineView;
export 'src/diagram/mermaid_mindmap.dart'
    show Mindmap, MindmapNode, parseMindmap, MermaidMindmapView;
export 'src/diagram/mermaid_sequence.dart'
    show SequenceDiagram, SeqMessage, parseSequence, SequenceDiagramView;
export 'src/diagram/mermaid_flowchart.dart'
    show
        Flowchart,
        FlowNode,
        FlowEdge,
        FlowDirection,
        FlowShape,
        parseFlowchart,
        FlowchartView;
export 'src/diagram/mermaid_state.dart' show parseStateDiagram;
export 'src/diagram/mermaid_class.dart'
    show
        ClassDiagram,
        ClassBox,
        ClassRelation,
        ClassRelationKind,
        parseClassDiagram,
        ClassDiagramView;
export 'src/diagram/mermaid_er.dart' show parseEntityRelationship;
export 'src/diagram/mermaid_gantt.dart'
    show Gantt, GanttTask, parseGantt, GanttView;
