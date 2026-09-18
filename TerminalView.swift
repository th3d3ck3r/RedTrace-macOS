import SwiftUI
import AppKit

struct InteractiveTerminalView: NSViewRepresentable {
    let model: TerminalModel; let send: (Data) -> Void
    func makeNSView(context: Context) -> NSScrollView { let s=NSScrollView();s.drawsBackground=false;s.hasVerticalScroller=true; let t=TerminalNSTextView();t.model=model;t.send=send;t.isEditable=false;t.isSelectable=true;t.drawsBackground=false;t.font=NSFont.monospacedSystemFont(ofSize:12,weight:.regular);t.textColor = .systemRed;t.textContainerInset=NSSize(width:12,height:10);s.documentView=t;context.coordinator.render(t,s,model);return s }
    func updateNSView(_ s:NSScrollView, context:Context) { if let t=s.documentView as? TerminalNSTextView { t.model=model;t.send=send;context.coordinator.render(t,s,model) } }
    func makeCoordinator()->Coordinator { Coordinator() }
    final class Coordinator { var revision=0; func render(_ text:NSTextView,_ scroll:NSScrollView,_ model:TerminalModel) { let at=NSMutableAttributedString(); for row in model.lines() { for cell in row { let st=cell.style; var attrs:[NSAttributedString.Key:Any]=[.font:NSFont.monospacedSystemFont(ofSize:12,weight:st.bold ? .bold:.regular),.foregroundColor:st.foreground.rgb ?? NSColor.systemRed]; if let bg=st.background.rgb {attrs[.backgroundColor]=bg};if st.underline{attrs[.underlineStyle]=NSUnderlineStyle.single.rawValue};if st.italic{attrs[.obliqueness]=0.16};at.append(NSAttributedString(string:String(cell.character),attributes:attrs)) };at.append(NSAttributedString(string:"\n")) }; let follow=scroll.contentView.bounds.maxY >= text.bounds.maxY-36;text.textStorage?.setAttributedString(at);if follow { DispatchQueue.main.async { scroll.contentView.scroll(to:NSPoint(x:0,y:max(0,text.bounds.height-scroll.contentSize.height)));scroll.reflectScrolledClipView(scroll.contentView) } } } }
}
final class TerminalNSTextView: NSTextView {
    var model: TerminalModel?; var send: ((Data)->Void)?
    override var acceptsFirstResponder: Bool { true }
    override func keyDown(with event:NSEvent) { if event.modifierFlags.contains(.command) { super.keyDown(with:event); return }; let flags=event.modifierFlags; let data:Data?; switch event.keyCode { case 36: data=Data("\r".utf8);case 48:data=Data("\t".utf8);case 53:data=Data([27]);case 51:data=Data([127]);case 123:data=Data("\u{1b}[D".utf8);case 124:data=Data("\u{1b}[C".utf8);case 125:data=Data("\u{1b}[B".utf8);case 126:data=Data("\u{1b}[A".utf8);case 115:data=Data("\u{1b}[H".utf8);case 119:data=Data("\u{1b}[F".utf8);case 116:data=Data("\u{1b}[5~".utf8);case 121:data=Data("\u{1b}[6~".utf8);default: if flags.contains(.control), let c=event.charactersIgnoringModifiers?.lowercased().utf8.first { data=Data([c & 0x1f]) } else if let chars=event.characters { data=Data(chars.utf8) } else {data=nil} };if let data {send?(data)} }
    override func paste(_ sender:Any?) { guard let value=NSPasteboard.general.string(forType:.string) else{return};let data=Data(value.utf8);if model?.bracketedPaste == true {send?(Data("\u{1b}[200~".utf8)+data+Data("\u{1b}[201~".utf8))}else{send?(data)} }
}
