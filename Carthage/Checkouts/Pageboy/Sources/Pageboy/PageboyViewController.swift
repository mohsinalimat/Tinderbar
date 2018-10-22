//
//  PageboyViewController.swift
//  Pageboy
//
//  Created by Merrick Sapsford on 04/01/2017.
//  Copyright © 2018 UI At Six. All rights reserved.
//

import UIKit

/// A simple, highly informative page view controller.
open class PageboyViewController: UIViewController {
    
    // MARK: Types
    
    /// Completion of a page scroll.
    public typealias PageScrollCompletion = (_ newViewController: UIViewController, _ animated: Bool, _ finished: Bool) -> Void

    // MARK: Properties
    
    internal var pageViewController: UIPageViewController?
    /// An invisible scroll view used for silently influencing navigation bar titles.
    internal var invisibleScrollView: UIScrollView?
    internal var previousPagePosition: CGFloat?
    internal var expectedTransitionIndex: PageIndex?
    internal let childScrollObserver = ScrollObservationService()

    /// The orientation that the page view controller transitions on.
    public var navigationOrientation: UIPageViewController.NavigationOrientation = .horizontal {
        didSet {
            reconfigurePageViewController()
        }
    }
    /// The spacing between pages.
    public var interPageSpacing: CGFloat = 0.0 {
        didSet {
            reconfigurePageViewController()
        }
    }
    
    #if os(iOS)
    
    /// Preferred status bar style of the current view controller.
    open override var preferredStatusBarStyle: UIStatusBarStyle {
        if let currentViewController = currentViewController {
            return currentViewController.preferredStatusBarStyle
        }
        return super.preferredStatusBarStyle
    }
    /// Preferred status bar hidden of the current view controller.
    open override var prefersStatusBarHidden: Bool {
        if let currentViewController = currentViewController {
            return currentViewController.prefersStatusBarHidden
        }
        return super.prefersStatusBarHidden
    }
    
    #endif
    
    /// The object that is the data source for the page view controller. (Defaults to self)
    public weak var dataSource: PageboyViewControllerDataSource? {
        didSet {
            reloadData()
        }
    }
    /// The object that is the delegate for the page view controller.
    public weak var delegate: PageboyViewControllerDelegate?
    
    
    // default is YES. if NO, we immediately call -touchesShouldBegin:withEvent:inContentView:. this has no effect on presses
    public var delaysContentTouches: Bool = true {
        didSet {
            pageViewController?.scrollView?.delaysContentTouches = delaysContentTouches
        }
    }
    /// default YES. if YES, bounces past edge of content and back again.
    public var bounces: Bool = true
    // Whether client content appears on both sides of each page. If 'NO', content on page front will partially show through back.
    // If 'UIPageViewControllerSpineLocationMid' is set, 'doubleSided' is set to 'YES'. Setting 'NO' when spine location is mid results in an exception.
    public var isDoubleSided: Bool = false {
        didSet {
            pageViewController?.isDoubleSided = isDoubleSided
        }
    }
    
    /// Whether the page view controller is currently being touched.
    public var isTracking: Bool {
        return pageViewController?.scrollView?.isTracking ?? false
    }
    /// Whether the page view controller is currently being dragged.
    public var isDragging: Bool {
            return pageViewController?.scrollView?.isDragging ?? false
    }
    // Wether the user isn't dragging (touch up) but page view controller is still moving.
    public var isDecelerating: Bool {
        return pageViewController?.scrollView?.isDecelerating ?? false
    }
    /// Whether user interaction is enabled on the page view controller.
    ///
    /// Default is TRUE
    public var isUserInteractionEnabled: Bool = true {
        didSet {
            pageViewController?.scrollView?.isUserInteractionEnabled = isUserInteractionEnabled
        }
    }
    /// Whether scroll is enabled on the page view controller.
    ///
    /// Default is TRUE.
    public var isScrollEnabled: Bool = true {
        didSet {
            pageViewController?.scrollView?.isScrollEnabled = isScrollEnabled
        }
    }
    /// Whether the page view controller should infinitely scroll at the end of page ranges.
    ///
    /// Default is FALSE.
    public var isInfiniteScrollEnabled: Bool = false {
        didSet {
            reloadCurrentPageSoftly()
        }
    }
    /// Whether the page view controller is currently animating a scroll between pages.
    private(set) internal var isScrollingAnimated = false {
        didSet {
            isUserInteractionEnabled = !isScrollingAnimated
        }
    }
    /// Whether the view controllers in the page view controller are currently updating.
    internal var isUpdatingViewControllers: Bool = false

    /// Custom transition to use when animating scrolls between pages.
    /// Setting this to `nil` will revert to using the standard UIPageViewController animation.
    public var transition: Transition?
    /// The display link for transitioning.
    internal var transitionDisplayLink: CADisplayLink?
    /// The active transition operation.
    internal var activeTransitionOperation: TransitionOperation?
    
    /// The number of view controllers in the page view controller.
    internal var viewControllerCount: Int?
    /// A map of view controllers and related page indexes.
    internal lazy var viewControllerMap = [UIViewController: PageIndex]()
    
    /// The number of pages in the page view controller.
    public var pageCount: Int? {
        return viewControllerCount
    }
    
    /// The page index that is currently the target of a transition. This will align with currentIndex if no transition is active.
    internal var targetIndex: PageIndex?
    /// The page index that the page view controller is currently at.
    public internal(set) var currentIndex: PageIndex? {
        didSet {
            targetIndex = currentIndex
            guard let currentIndex = currentIndex else {
                return
            }
            update(forNew: currentIndex, from: oldValue)
        }
    }
    /// The relative page position that the page view controller is currently at.
    public internal(set) var currentPosition: CGPoint?
    /// The view controller that the page view controller is currently at.
    public weak var currentViewController: UIViewController? {
        guard let currentIndex = currentIndex,
            viewControllerCount ?? 0 > currentIndex else {
                return nil
        }
        return pageViewController?.viewControllers?.last
    }
    /// Whether the page view controller position is currently resting on a page index.
    internal var isPositionedOnPageIndex: Bool {
        let orientatedCurrentPosition = navigationOrientation == .horizontal ? currentPosition?.x : currentPosition?.y
        return orientatedCurrentPosition?.truncatingRemainder(dividingBy: 1) == 0
    }
    
    /// Auto Scroller for automatic time-based page transitions.
    public let autoScroller = PageboyAutoScroller()
    
    /// Whether to show the built-in UIPageViewController page control.
    @available(*, unavailable, message: "Temporarily unavailable due to iOS 11.2 UIPageViewController issue. See here: https://github.com/uias/Pageboy/issues/128")
    public var showsPageControl: Bool = false
    
    // MARK: Lifecycle

    open override func viewDidLoad() {
        super.viewDidLoad()

        autoScroller.handler = self
        childScrollObserver.delegate = self
        
        setUpPageViewController()
    }
    
    open override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)

        // If we are not at expected index when we appear - force a move to the expected index.
        if let expectedTransitionIndex = expectedTransitionIndex, expectedTransitionIndex != currentIndex {
            scrollToPage(.at(index: expectedTransitionIndex),
                         animated: false,
                         force: true)
        }
    }
    
    open override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)

        if autoScroller.isEnabled {
            autoScroller.resume()
        }
    }
    
    open override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)

        if autoScroller.isEnabled {
            autoScroller.pause()
        }
    }

    open override func viewWillTransition(to size: CGSize,
                                          with coordinator: UIViewControllerTransitionCoordinator) {
        super.viewWillTransition(to: size, with: coordinator)

        // ignore scroll updates during orientation change
        pageViewController?.scrollView?.delegate = nil
        coordinator.animate(alongsideTransition: nil) { [weak self] (_) in
            self?.pageViewController?.scrollView?.delegate = self
        }
    }
    
    // MARK: View Controller Updates
    
    /// Insert a new page into the page view controller.
    ///
    /// - Parameters:
    ///   - index: The index to insert the page at.
    ///   - updateBehavior: Behavior to execute after the page was inserted.
    open func insertPage(at index: PageIndex,
                         then updateBehavior: PageUpdateBehavior = .scrollToUpdate) {
    verifyNewPageCount(then: { (oldPageCount, newPageCount) in
        assert(newPageCount > oldPageCount,
                "Attempt to insert page at \(index) but there are only \(newPageCount) pages after the update")

        guard let newViewController = dataSource?.viewController(for: self, at: index) else {
            assertionFailure("Expected to find inserted UIViewController at page \(index)")
            return
        }

        viewControllerCount = newPageCount
        viewControllerMap.removeAll()

        performUpdates(for: index,
                        viewController: newViewController,
                        updateBehavior: updateBehavior,
                        indexOperation: { (index, newIndex) in

                        if index > newIndex {
                            currentIndex = index + 1
                        }
        })
    })
    }
    
    /// Delete an existing page from the page view controller.
    ///
    /// - Parameters:
    ///   - index: The index to delete the page from.
    ///   - updateBehavior: Behavior to execute after the page was deleted.
    open func deletePage(at index: PageIndex,
                         then updateBehavior: PageUpdateBehavior = .doNothing) {
        verifyNewPageCount(then: { (oldPageCount, newPageCount) in
            assert(index < oldPageCount,
                   "Attempting to delete page at \(index) but there were only \(oldPageCount) pages before the update")
            assert(newPageCount < oldPageCount,
                   "Attempt to delete page at \(index) but there are \(newPageCount) pages after the update")

            let sanitizedIndex = min(index, newPageCount - 1)
            guard let newViewController = dataSource?.viewController(for: self, at: sanitizedIndex) else {
                return
            }

            viewControllerCount = newPageCount
            viewControllerMap.removeAll()

            performUpdates(for: sanitizedIndex,
                           viewController: newViewController,
                           updateBehavior: updateBehavior,
                           indexOperation: { (index, newIndex) in

                            if index > newIndex {
                                currentIndex = index - 1
                            }
            })
        })
    }
}

// MARK: - Paging Updates
public extension PageboyViewController {
    
    /// Scroll the page view controller to a new page.
    ///
    /// - parameter page: The index of the new page.
    /// - parameter animated: Whether to animate the transition.
    /// - parameter completion: The completion closure.
    /// - Returns: Whether the scroll was executed.
    @discardableResult
    public func scrollToPage(_ page: Page,
                             animated: Bool,
                             completion: PageScrollCompletion? = nil) -> Bool {
        return scrollToPage(page,
                            animated: animated,
                            force: false,
                            completion: completion)
    }
    
    /// Scroll the page view controller to a new page.
    ///
    /// - parameter page: The index of the new page.
    /// - parameter animated: Whether to animate the transition.
    /// - parameter force: Whether to force the scroll, ignoring current animation & positional status.
    /// - parameter completion: The completion closure.
    /// - Returns: Whether the scroll was executed.
    @discardableResult
    internal func scrollToPage(_ page: Page,
                               animated: Bool,
                               force: Bool,
                               completion: PageScrollCompletion? = nil) -> Bool {
        guard let pageViewController = pageViewController, isSafeToScrollToANewPage(ignoringPosition: force) else {
            return false
        }

        let rawIndex = page.indexValue(in: self)
        if rawIndex != currentIndex {

            // guard against invalid page indexing
            guard rawIndex >= 0 && rawIndex < viewControllerCount ?? 0, let viewController = fetchViewController(at: rawIndex) else {
                return false
            }

            self.pageViewController(pageViewController,
                                    willTransitionTo: [viewController],
                                    animated: animated)

            isScrollingAnimated = animated
            let direction = NavigationDirection.forPageScroll(to: page, at: rawIndex, in: self)

            let transitionCompletion: TransitionOperation.Completion = { [weak self] (finished) in
                if finished {
                    let isVertical = self?.navigationOrientation == .vertical
                    let currentPosition = CGPoint(x: isVertical ? 0.0 : CGFloat(rawIndex),
                                                  y: isVertical ? CGFloat(rawIndex) : 0.0)
                    self?.currentPosition = currentPosition
                    self?.currentIndex = rawIndex

                    // if not animated call position delegate update manually
                    if !animated {
                        if let self = self {
                            self.delegate?.pageboyViewController(self,
                                                                 didScrollTo: currentPosition,
                                                                 direction: direction,
                                                                 animated: animated)
                        }
                        self?.expectedTransitionIndex = nil
                    }
                }

                self?.autoScroller.didFinishScrollIfEnabled()
                completion?(viewController, animated, finished)
                self?.isScrollingAnimated = false
            }

            updateViewControllers(to: [viewController],
                                  from: currentIndex ?? 0,
                                  to: rawIndex,
                                  direction: direction,
                                  animated: animated,
                                  async: true,
                                  force: force,
                                  completion: transitionCompletion)

            return true

        } else {
            guard let viewController = fetchViewController(at: rawIndex) else {
                return false
            }
            autoScroller.didFinishScrollIfEnabled()
            completion?(viewController, animated, false)

            return false
        }
    }
    
    private func isSafeToScrollToANewPage(ignoringPosition: Bool) -> Bool {
        guard let pageViewController = pageViewController else {
            return false
        }
        if ignoringPosition { // if ignoring position then escape and mark as safe.
            return true
        }

        // guard against any active interactive scrolling
        guard pageViewController.scrollView?.isProbablyActiveInScroll == false &&
            isPositionedOnPageIndex else {
                return false
        }
        // guard against any current transition operation
        guard isScrollingAnimated == false else {
            return false
        }

        return true
    }

    private func update(forNew currentIndex: PageIndex, from oldIndex: PageIndex?) {
        
        #if os(iOS)
            UIView.animate(withDuration: 0.25) {
                self.setNeedsStatusBarAppearanceUpdate()
            }
        #endif
        
        // ensure position keeps in sync
        currentPosition = CGPoint(x: navigationOrientation == .horizontal ? CGFloat(currentIndex) : 0.0,
                                  y: navigationOrientation == .vertical ? CGFloat(currentIndex) : 0.0)
        let direction = NavigationDirection.forPosition(CGFloat(currentIndex),
                                                        previous: CGFloat(oldIndex ?? currentIndex))
        delegate?.pageboyViewController(self,
                                        didScrollToPageAt: currentIndex,
                                        direction: direction,
                                        animated: isScrollingAnimated)
    }
}