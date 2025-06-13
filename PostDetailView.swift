//
//  PostDetailView.swift
//  FitSpo
//
//  Displays a single post + AI outfit scan.
//

import SwiftUI
import FirebaseAuth
import FirebaseFirestore
import CoreLocation
import UIKit   // ZoomableAsyncImage is now its own file

// ─────────────────────────────────────────────────────────────
struct PostDetailView: View {

    // ── Injected model ─────────────────────────────────────────
    let post: Post
    @Environment(\.dismiss) private var dismiss

    // ── Author info ────────────────────────────────────────────
    @State private var authorName      = ""
    @State private var authorAvatarURL = ""
    @State private var isLoadingAuthor = true

    // ── Location chip ─────────────────────────────────────────
    @State private var locationName = ""

    // ── Like state ────────────────────────────────────────────
    @State private var isLiked       : Bool
    @State private var likesCount    : Int
    @State private var showHeartBurst = false

    // ── Comments state ────────────────────────────────────────
    @State private var commentCount  : Int = 0
    @State private var showComments  = false

    // ── Share / chat state ────────────────────────────────────
    @State private var showShareSheet   = false
    @State private var shareChat: Chat?
    @State private var navigateToChat   = false

    // ── Delete UX state ───────────────────────────────────────
    @State private var isDeleting        = false
    @State private var showDeleteConfirm = false

    // ── Outfit-scan state ─────────────────────────────────────
    @State private var isScanning   = false
    @State private var outfitItems: [OutfitItem] = []
    @State private var showOutfitSheet = false

    // Live listener
    @State private var postListener: ListenerRegistration?

    // Image aspect-ratio (h ÷ w)
    @State private var imgRatio: CGFloat? = nil

    // Tags loaded from Firestore
    @State private var postTags: [UserTag] = []

    // ─────────────────────────────────────────────────────────
    init(post: Post) {
        self.post = post
        _isLiked    = State(initialValue: post.isLiked)
        _likesCount = State(initialValue: post.likes)
    }

    // =========================================================
    // MARK: Body
    // =========================================================
    var body: some View {
        ZStack(alignment: .bottom) {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    header
                    postImage
                    actionRow
                    captionRow
                    timestampRow
                    Spacer(minLength: 32)
                }
                .padding(.top)
            }

            if showComments {
                CommentsOverlay(
                    post: post,
                    isPresented: $showComments,
                    onCommentCountChange: { commentCount = $0 }
                )
                .transition(.move(edge: .bottom))
            }
        }
        .animation(.easeInOut, value: showComments)
        .navigationTitle("Post")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if post.userId == Auth.auth().currentUser?.uid {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Delete", role: .destructive) { showDeleteConfirm = true }
                }
            }
        }
        .alert("Delete Post?", isPresented: $showDeleteConfirm) {
            Button("Delete", role: .destructive, action: performDelete)
            Button("Cancel",  role: .cancel) {}
        }
        .overlay {
            if isDeleting {
                ProgressView("Deleting…")
                    .padding()
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
            }
        }
        .sheet(isPresented: $showShareSheet) {
            ShareToUserView { uid in
                showShareSheet = false
                sharePost(to: uid)
            }
        }
        .sheet(isPresented: $showOutfitSheet) {
            OutfitItemSheet(
                items: outfitItems,
                isScanning: isScanning,
                isPresented: $showOutfitSheet
            )
            .presentationDetents([.fraction(0.45), .large])
        }
        .background {
            if let chat = shareChat {
                NavigationLink(destination: ChatDetailView(chat: chat),
                               isActive: $navigateToChat) { EmptyView() }
                    .hidden()
            }
        }
        .onAppear {
            attachPostListener()
            fetchAuthor()
            fetchLocationName()
            fetchCommentCount()
            fetchTags()
        }
        .onDisappear { postListener?.remove() }
    }

    // =========================================================
    // MARK: Sub-views
    // =========================================================

    private var header: some View {
        HStack(alignment: .top, spacing: 12) {
            NavigationLink(destination: ProfileView(userId: post.userId)) {
                avatarView
            }

            VStack(alignment: .leading, spacing: 4) {
                NavigationLink(destination: ProfileView(userId: post.userId)) {
                    Text(isLoadingAuthor ? "Loading…" : authorName)
                        .font(.headline)
                }
                if !locationName.isEmpty {
                    Text(locationName)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
            }
            Spacer()
        }
        .padding(.horizontal)
    }

    private var postImage: some View {
        GeometryReader { geo in
            if let url = URL(string: post.imageURL) {
                ZoomableAsyncImage(url: url, aspectRatio: $imgRatio)
                    .frame(width:  geo.size.width,
                           height: (imgRatio ?? 1) * geo.size.width)
                    .clipped()
                    .simultaneousGesture(
                        TapGesture(count: 2).onEnded { handleDoubleTapLike() }
                    )
                    .overlay(HeartBurstView(trigger: $showHeartBurst))
                    // clickable user tags
                    .overlay(
                        ForEach(postTags) { tag in
                            NavigationLink(destination: ProfileView(userId: tag.id)) {
                                Text(tag.displayName)
                                    .font(.caption2.weight(.semibold))
                                    .padding(6)
                                    .background(.thinMaterial, in: Capsule())
                            }
                            .buttonStyle(.plain)
                            .position(
                                x: tag.xNorm * geo.size.width,
                                y: tag.yNorm * geo.size.width * (imgRatio ?? 1)
                            )
                        }
                    )
            } else {
                ZStack {
                    Color.gray.opacity(0.2)
                    Image(systemName: "photo")
                        .font(.largeTitle)
                        .foregroundColor(.white.opacity(0.7))
                }
            }
        }
        .frame(height: UIScreen.main.bounds.width * (imgRatio ?? 1))
    }

    private var actionRow: some View {
        HStack(spacing: 24) {
            Button(action: toggleLike) {
                Image(systemName: isLiked ? "heart.fill" : "heart")
                    .font(.title2)
                    .foregroundColor(isLiked ? .red : .primary)
            }
            Text("\(likesCount)")
                .font(.subheadline.weight(.semibold))

            Button { showComments = true } label: {
                Image(systemName: "bubble.right").font(.title2)
            }
            Text("\(commentCount)")
                .font(.subheadline.weight(.semibold))

            Button {
                showOutfitSheet = true
                scanOutfit()
            } label: {
                Image(systemName: "hanger").font(.title2)
            }

            Button { showShareSheet = true } label: {
                Image(systemName: "paperplane").font(.title2)
            }
            Spacer()
        }
        .padding(.horizontal)
    }

    private var captionRow: some View {
        HStack(alignment: .top, spacing: 4) {
            NavigationLink(destination: ProfileView(userId: post.userId)) {
                Text(isLoadingAuthor ? "Loading…" : authorName)
                    .fontWeight(.semibold)
            }
            Text(post.caption)
        }
        .padding(.horizontal)
    }

    private var timestampRow: some View {
        Text(post.timestamp, style: .time)
            .font(.caption)
            .foregroundColor(.gray)
            .padding(.horizontal)
    }

    @ViewBuilder private var avatarView: some View {
        Group {
            if let url = URL(string: authorAvatarURL), !authorAvatarURL.isEmpty {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .empty: ProgressView()
                    case .success(let img): img.resizable().scaledToFill()
                    default: Image(systemName: "person.crop.circle.fill").resizable()
                    }
                }
            } else {
                Image(systemName: "person.crop.circle.fill")
                    .resizable()
                    .foregroundColor(.gray)
            }
        }
        .frame(width: 40, height: 40)
        .clipShape(Circle())
    }

    // =========================================================
    // MARK: Firestore helpers
    // =========================================================
    private func attachPostListener() {
        guard postListener == nil else { return }
        Firestore.firestore().collection("posts").document(post.id)
            .addSnapshotListener { snap, _ in
                guard let d = snap?.data() else { return }
                likesCount   = d["likes"] as? Int ?? likesCount
                commentCount = d["commentsCount"] as? Int ?? commentCount
                if let likedBy = d["likedBy"] as? [String],
                   let uid = Auth.auth().currentUser?.uid {
                    isLiked = likedBy.contains(uid)
                }
            }
    }

    private func fetchAuthor() {
        Firestore.firestore().collection("users")
            .document(post.userId)
            .getDocument { snap, _ in
                isLoadingAuthor = false
                let d = snap?.data() ?? [:]
                authorName      = d["displayName"] as? String ?? "Unknown"
                authorAvatarURL = d["avatarURL"]   as? String ?? ""
            }
    }

    private func fetchLocationName() {
        guard let lat = post.latitude, let lon = post.longitude else { return }
        CLGeocoder().reverseGeocodeLocation(
            CLLocation(latitude: lat, longitude: lon)
        ) { places, _ in
            guard let p = places?.first else { return }
            var parts = [String]()
            if let city   = p.locality           { parts.append(city) }
            if let region = p.administrativeArea { parts.append(region) }
            if parts.isEmpty, let country = p.country { parts.append(country) }
            locationName = parts.joined(separator: ", ")
        }
    }

    private func fetchCommentCount() {
        NetworkService.shared.fetchComments(for: post.id) { res in
            if case .success(let list) = res { commentCount = list.count }
        }
    }

    private func fetchTags() {
        NetworkService.shared.fetchTags(for: post.id) { res in
            if case .success(let list) = res { postTags = list }
        }
    }

    // =========================================================
    // MARK: Actions
    // =========================================================
    private func toggleLike() {
        isLiked.toggle()
        likesCount += isLiked ? 1 : -1
        NetworkService.shared.toggleLike(post: post) { _ in }
    }

    private func handleDoubleTapLike() {
        UIImpactFeedbackGenerator(style: .rigid).impactOccurred()
        showHeartBurst = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            showHeartBurst = false
        }
        if !isLiked { toggleLike() }
    }

    private func performDelete() {
        isDeleting = true
        NetworkService.shared.deletePost(id: post.id) { res in
            DispatchQueue.main.async {
                isDeleting = false
                if case .success = res { dismiss() }
            }
        }
    }

    private func sharePost(to userId: String) {
        guard let me = Auth.auth().currentUser?.uid else { return }
        let pair = [me, userId].sorted()
        NetworkService.shared.createChat(participants: pair) { res in
            switch res {
            case .success(let chat):
                NetworkService.shared.sendPost(
                    chatId: chat.id,
                    postId: post.id
                ) { _ in }
                DispatchQueue.main.async {
                    shareChat = chat
                    navigateToChat = true
                }
            case .failure(let err):
                print("Chat creation error:", err)
            }
        }
    }

    // MARK: Outfit-AI scan
    private func scanOutfit() {
        isScanning  = true
        outfitItems = []

        NetworkService.shared.scanOutfit(
            postId:   post.id,
            imageURL: post.imageURL
        ) { res in
            DispatchQueue.main.async {
                isScanning = false
                if case .success(let items) = res {
                    outfitItems = items
                } else {
                    outfitItems = []   // show empty state / toast
                }
            }
        }
    }
}
