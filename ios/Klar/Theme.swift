import SwiftUI

extension Color {
    static let klarGreen = Color(red:0.25, green:0.47, blue:0.30)
    static let klarInk = Color(red:0.08, green:0.10, blue:0.10)
    static let klarBackground = Color(red:0.965, green:0.969, blue:0.960)
    static let klarSoftGreen = Color(red:0.89, green:0.94, blue:0.89)
}

struct KlarCard<Content: View>: View {
    let content: Content
    init(@ViewBuilder content: () -> Content) { self.content = content() }
    var body: some View {
        content
            .padding(17)
            .frame(maxWidth:.infinity,alignment:.leading)
            .background(Color(uiColor:.secondarySystemGroupedBackground),in:RoundedRectangle(cornerRadius:20,style:.continuous))
            .overlay(RoundedRectangle(cornerRadius:20,style:.continuous).stroke(.primary.opacity(0.035),lineWidth:1))
    }
}

struct ScreenTitle: View {
    let title: String
    var subtitle: String? = nil
    var body: some View {
        VStack(alignment:.leading,spacing:4) {
            Text(title).font(.system(size:33,weight:.bold,design:.rounded)).foregroundStyle(.primary)
            if let subtitle { Text(subtitle).font(.subheadline).foregroundStyle(.secondary) }
        }.frame(maxWidth:.infinity,alignment:.leading)
    }
}

struct PrimaryButton: View {
    let title: String
    var symbol: String? = nil
    var action: () -> Void
    var body: some View {
        Button(action:action) {
            HStack(spacing:8) {
                if let symbol { Image(systemName:symbol) }
                Text(title).fontWeight(.semibold)
            }
            .frame(maxWidth:.infinity).padding(.vertical,15)
            .foregroundStyle(.white)
            .background(Color.klarGreen,in:RoundedRectangle(cornerRadius:15))
        }.buttonStyle(.plain)
    }
}

struct SectionLabel: View {
    let title: String
    var body: some View {
        Text(title).font(.system(.headline,design:.rounded))
            .frame(maxWidth:.infinity,alignment:.leading)
    }
}

struct EmptyHint: View {
    let symbol: String
    let title: String
    let message: String
    var body: some View {
        VStack(spacing:9) {
            Image(systemName:symbol).font(.system(size:28)).foregroundStyle(Color.klarGreen)
            Text(title).font(.headline)
            Text(message).font(.footnote).foregroundStyle(.secondary).multilineTextAlignment(.center)
        }
        .frame(maxWidth:.infinity).padding(.vertical,24)
    }
}

struct TinyPill: View {
    let title: String
    let color: Color
    var body: some View {
        Text(title).font(.system(size:11,weight:.semibold))
            .foregroundStyle(color)
            .padding(.horizontal,9).padding(.vertical,5)
            .background(color.opacity(0.10),in:Capsule())
    }
}

struct TaskRow: View {
    let task: TaskEntry
    let toggle: () -> Void
    var body: some View {
        HStack(spacing:12) {
            Button(action:toggle) {
                Image(systemName:task.completed ? "checkmark.square.fill":"square")
                    .font(.system(size:22)).foregroundStyle(task.completed ? Color.klarGreen : Color.secondary)
            }.buttonStyle(.plain)
            VStack(alignment:.leading,spacing:3) {
                Text(task.title).font(.subheadline.weight(.medium))
                    .strikethrough(task.completed).foregroundStyle(task.completed ? .secondary : .primary)
                if let due = task.dueAt {
                    Text(due,format:.dateTime.day().month(.abbreviated()).hour().minute())
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            Spacer(minLength:6)
            if !task.completed && task.priority == "hoch" { TinyPill(title:"Hoch",color:.red) }
        }.padding(.vertical,9)
    }
}

struct RecurringRow: View {
    let recurring: RecurringEntry
    var body: some View {
        HStack(spacing:12) {
            Image(systemName:recurring.kind == "abo" ? "repeat":"house")
                .font(.system(size:15,weight:.semibold))
                .frame(width:35,height:35)
                .background(Color.klarSoftGreen,in:RoundedRectangle(cornerRadius:10))
            VStack(alignment:.leading,spacing:3) {
                Text(recurring.title).font(.subheadline.weight(.medium))
                Text("Fällig: \(recurring.nextDue)").font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Text("−\(recurring.amountCents.euros)").font(.subheadline.weight(.semibold))
        }.padding(.vertical,7)
    }
}

extension View {
    func klarScreen() -> some View {
        background(Color(uiColor:.systemGroupedBackground)).tint(.klarGreen)
    }
}
