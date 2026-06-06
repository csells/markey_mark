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
        HorizontalRuleNode,
        ImageNode,
        MathBlockNode,
        TableNode,
        TableAlign,
        MermaidNode,
        FrontMatterNode,
        BlockType,
        NodeIds;
export 'src/model/document.dart' show Document;
export 'src/model/position.dart'
    show DocumentPosition, NodePosition, TextNodePosition, AtomicNodePosition;
export 'src/model/selection.dart' show DocumentSelection;

// Editing (L4)
export 'src/editing/operations.dart'
    show Operation, InsertNodeOp, DeleteNodeOp, ReplaceNodeOp;
export 'src/editing/transaction.dart' show EditTransaction;
export 'src/editing/editor.dart' show Editor;
export 'src/editing/commands.dart' show EditCommands;
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

// Markdown pipeline (L0)
export 'src/markdown/decoder.dart' show MarkdownDecoder;
export 'src/markdown/encoder.dart' show MarkdownEncoder;
export 'src/markdown/markdown.dart' show Markdown;

// Widget + controller (L7)
export 'src/widget/controller.dart'
    show MarkdownEditorController, EditorMode, DocumentStats;
export 'src/widget/markdown_editor.dart' show MarkdownEditor;
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
