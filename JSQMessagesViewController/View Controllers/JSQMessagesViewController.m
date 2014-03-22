//
//  Created by Jesse Squires
//  http://www.hexedbits.com
//
//
//  Documentation
//  http://cocoadocs.org/docsets/JSMessagesViewController
//
//
//  The MIT License
//  Copyright (c) 2014 Jesse Squires
//  http://opensource.org/licenses/MIT
//

#import "JSQMessagesViewController.h"

#import <DAKeyboardControl/DAKeyboardControl.h>


static void * kJSQMessagesKeyValueObservingContext = &kJSQMessagesKeyValueObservingContext;

static NSString * const kJSQDefaultSender = @"JSQDefaultSender";



@interface JSQMessagesViewController () <JSQMessagesInputToolbarDelegate, UITextViewDelegate>

@property (weak, nonatomic) IBOutlet JSQMessagesCollectionView *collectionView;
@property (weak, nonatomic) IBOutlet JSQMessagesInputToolbar *inputToolbar;

@property (weak, nonatomic) IBOutlet NSLayoutConstraint *toolbarHeightContraint;
@property (weak, nonatomic) IBOutlet NSLayoutConstraint *toolbarBottomLayoutGuide;

@property (nonatomic, readonly) JSQMessagesCollectionViewFlowLayout *collectionViewLayout;

- (void)jsq_configureViewController;

- (void)jsq_prepareForRotation;

- (void)jsq_notifyDelegateDidSendMessage;
- (void)jsq_notifyDelegateDidPressAccessoryButton:(UIButton *)sender;

- (void)jsq_configureKeyboardControl;
- (void)jsq_updateKeyboardTriggerOffset;

- (BOOL)jsq_inputToolbarHasReachedMaximumHeight;
- (void)jsq_adjustInputToolbarForComposerTextViewContentSizeChange:(CGFloat)dy;
- (void)jsq_adjustInputToolbarHeightConstraintByDelta:(CGFloat)dy;
- (void)jsq_scrollComposerTextViewToBottomAnimated:(BOOL)animated;

- (void)jsq_updateCollectionViewInsets;
- (void)jsq_setCollectionViewInsetsTopValue:(CGFloat)top bottomValue:(CGFloat)bottom;

- (void)jsq_addObservers;
- (void)jsq_removeObservers;

@end



@implementation JSQMessagesViewController

#pragma mark - Class methods

+ (UINib *)nib
{
    return [UINib nibWithNibName:NSStringFromClass([JSQMessagesViewController class])
                          bundle:[NSBundle mainBundle]];
}

+ (instancetype)messagesViewController
{
    return [[[self class] alloc] initWithNibName:NSStringFromClass([JSQMessagesViewController class])
                                          bundle:[NSBundle mainBundle]];
}

#pragma mark - Initialization

- (void)jsq_configureViewController
{
    self.view.backgroundColor = [UIColor whiteColor];
    
    _toolbarHeightContraint.constant = kJSQMessagesInputToolbarHeightDefault;
    
    _collectionView.dataSource = self;
    _collectionView.delegate = self;
    _collectionView.keyboardDismissMode = UIScrollViewKeyboardDismissModeInteractive;
    
    ((JSQMessagesCollectionViewFlowLayout *)_collectionView.collectionViewLayout).delegate = self;
    
    _inputToolbar.delegate = self;
    _inputToolbar.contentView.textView.placeHolder = NSLocalizedString(@"New Message", @"Placeholder text for the message input text view");
    _inputToolbar.contentView.textView.delegate = self;
    
    _sender = kJSQDefaultSender;
    
    _autoScrollsToMostRecentMessage = YES;
    
    _outgoingCellIdentifier = [JSQMessagesCollectionViewCellOutgoing cellReuseIdentifier];
    _incomingCellIdentifier = [JSQMessagesCollectionViewCellIncoming cellReuseIdentifier];
}

- (instancetype)initWithNibName:(NSString *)nibNameOrNil bundle:(NSBundle *)nibBundleOrNil
{
    self = [super initWithNibName:nibNameOrNil bundle:nibBundleOrNil];
    if (self) {
        [self jsq_configureViewController];
    }
    return self;
}

- (instancetype)initWithCoder:(NSCoder *)aDecoder
{
    self = [super initWithCoder:aDecoder];
    if (self) {
        [[NSBundle mainBundle] loadNibNamed:NSStringFromClass([JSQMessagesViewController class])
                                      owner:self
                                    options:nil];
    }
    return self;
}

- (void)awakeFromNib
{
    [super awakeFromNib];
    [self jsq_configureViewController];
}

#pragma mark - Getters

- (JSQMessagesCollectionViewFlowLayout *)collectionViewLayout
{
    return (JSQMessagesCollectionViewFlowLayout *)self.collectionView.collectionViewLayout;
}

#pragma mark - View lifecycle

- (void)viewDidLoad
{
    [super viewDidLoad];
    [[JSQMessagesCollectionViewCell appearance] setFont:[UIFont systemFontOfSize:15.0f]];
    
    self.collectionViewLayout.springinessEnabled = NO;
    [self jsq_updateCollectionViewInsets];
}

- (void)viewWillAppear:(BOOL)animated
{
    [super viewWillAppear:animated];
    [self.view layoutIfNeeded];
    [self.collectionView.collectionViewLayout invalidateLayout];
    
    if (self.autoScrollsToMostRecentMessage) {
        [self scrollToBottomAnimated:NO];
        [self.collectionView.collectionViewLayout invalidateLayout];
    }
    
    [self jsq_updateKeyboardTriggerOffset];
    [self jsq_configureKeyboardControl];
}

- (void)viewDidAppear:(BOOL)animated
{
    [super viewDidAppear:animated];
    [self jsq_addObservers];
    
    self.collectionViewLayout.springinessEnabled = YES;
}

- (void)viewWillDisappear:(BOOL)animated
{
    [super viewWillDisappear:animated];
    [self.view removeKeyboardControl];
    [self jsq_removeObservers];
}

- (void)didReceiveMemoryWarning
{
    [super didReceiveMemoryWarning];
    NSLog(@"%s MEMORY WARNING!", __PRETTY_FUNCTION__);
}

#pragma mark - View rotation

- (BOOL)shouldAutorotate
{
    return YES;
}

- (NSUInteger)supportedInterfaceOrientations
{
    if ([UIDevice currentDevice].userInterfaceIdiom == UIUserInterfaceIdiomPhone) {
        return UIInterfaceOrientationMaskAllButUpsideDown;
    }
    return UIInterfaceOrientationMaskAll;
}

- (void)willRotateToInterfaceOrientation:(UIInterfaceOrientation)toInterfaceOrientation duration:(NSTimeInterval)duration
{
    [super willRotateToInterfaceOrientation:toInterfaceOrientation duration:duration];
    [self jsq_prepareForRotation];
}

- (void)willAnimateRotationToInterfaceOrientation:(UIInterfaceOrientation)toInterfaceOrientation duration:(NSTimeInterval)duration
{
    [super willAnimateRotationToInterfaceOrientation:toInterfaceOrientation duration:duration];
    [self jsq_prepareForRotation];
    
    // TODO: keyboard
}

- (void)jsq_prepareForRotation
{
    [self.collectionView.collectionViewLayout invalidateLayout];
    [self.inputToolbar.contentView.textView setNeedsDisplay];
}

#pragma mark - Messages view controller

- (void)finishSending
{
    UITextView *textView = self.inputToolbar.contentView.textView;
    textView.text = nil;
    
    [self.inputToolbar toggleSendButtonEnabled];
    
    [[NSNotificationCenter defaultCenter] postNotificationName:UITextViewTextDidChangeNotification object:textView];
    
    [self.collectionView reloadData];
    
    if (self.autoScrollsToMostRecentMessage) {
        [self scrollToBottomAnimated:YES];
    }
}

- (void)scrollToBottomAnimated:(BOOL)animated
{
    if ([self.collectionView numberOfSections] == 0) {
        return;
    }
    
    NSInteger items = [self.collectionView numberOfItemsInSection:0];
    
    if (items > 0) {
        [self.collectionView scrollToItemAtIndexPath:[NSIndexPath indexPathForItem:items - 1 inSection:0]
                                    atScrollPosition:UICollectionViewScrollPositionBottom
                                            animated:animated];
    }
}

#pragma mark - Collection view data source

- (id<JSQMessageData>)collectionView:(JSQMessagesCollectionView *)collectionView messageForItemAtIndexPath:(NSIndexPath *)indexPath
{
    NSAssert(NO, @"ERROR: subclasses of %@ must implement the data source method %@",
             [JSQMessagesViewController class],
             NSStringFromSelector(@selector(collectionView:messageForItemAtIndexPath:)));
    return nil;
}

- (NSInteger)collectionView:(UICollectionView *)collectionView numberOfItemsInSection:(NSInteger)section
{
    return 0;
}

- (NSInteger)numberOfSectionsInCollectionView:(UICollectionView *)collectionView
{
    return 1;
}

- (UICollectionViewCell *)collectionView:(JSQMessagesCollectionView *)collectionView cellForItemAtIndexPath:(NSIndexPath *)indexPath
{
    id<JSQMessageData> messageData = [collectionView.dataSource collectionView:collectionView messageForItemAtIndexPath:indexPath];
    
    NSString *messageSender = [messageData sender];
    BOOL isOutgoingMessage = [messageSender isEqualToString:self.sender];
    
    NSString *cellIdentifier = isOutgoingMessage ? self.outgoingCellIdentifier : self.incomingCellIdentifier;
    JSQMessagesCollectionViewCell *cell = [collectionView dequeueReusableCellWithReuseIdentifier:cellIdentifier forIndexPath:indexPath];
    
    JSQMessagesCollectionViewFlowLayout *collectionViewLayout = (JSQMessagesCollectionViewFlowLayout *)collectionView.collectionViewLayout;
    
    cell.messageBubbleImageView = [collectionViewLayout.delegate collectionView:collectionView
                                                                         layout:collectionViewLayout
                                              bubbleImageViewForItemAtIndexPath:indexPath
                                                                         sender:messageSender];
    
    cell.avatarImageView = [collectionViewLayout.delegate collectionView:collectionView
                                                                  layout:collectionViewLayout
                                       avatarImageViewForItemAtIndexPath:indexPath
                                                                  sender:messageSender];
    
    cell.textView.text = [messageData text];
    
//    cell.textView.dataDetectorTypes = UIDataDetectorTypeAll;
    cell.textView.selectable = NO;
    
    cell.backgroundColor = self.collectionView.backgroundColor;
    
    
    
    // -----------------------------------------------
    
    
    cell.cellTopLabel.attributedText = [[JSQMessagesTimestampFormatter sharedFormatter] attributedTimestampForDate:[messageData date]];
    cell.messageBubbleTopLabel.text = messageSender;
    
    
    if (isOutgoingMessage) {
        cell.cellBottomLabel.text = @"sent";
        cell.textView.textColor = [UIColor whiteColor];
        cell.messageBubbleTopLabel.textInsets = UIEdgeInsetsMake(0.0f, 0.0f, 0.0f,
                                                                 kJSQMessagesCollectionViewCellMessageBubbleTopLabelHorizontalPaddingDefault);
    }
    else {
        cell.cellBottomLabel.text = @"recieved";
        cell.textView.textColor = [UIColor blackColor];
        cell.messageBubbleTopLabel.textInsets = UIEdgeInsetsMake(0.0f, kJSQMessagesCollectionViewCellMessageBubbleTopLabelHorizontalPaddingDefault,
                                                                 0.0f, 0.0f);
    }
    
//    cell2.textView.backgroundColor = [[UIColor redColor] colorWithAlphaComponent:0.5];
    
    return cell;
}

- (UICollectionReusableView *)collectionView:(UICollectionView *)collectionView
           viewForSupplementaryElementOfKind:(NSString *)kind
                                 atIndexPath:(NSIndexPath *)indexPath
{
    return nil; // TODO:
}

#pragma mark - Collection view delegate

// TODO:

#pragma mark - Collection view delegate flow layout

- (UIImageView *)collectionView:(JSQMessagesCollectionView *)collectionView
                         layout:(JSQMessagesCollectionViewFlowLayout *)layout bubbleImageViewForItemAtIndexPath:(NSIndexPath *)indexPath
                         sender:(NSString *)sender
{
    NSAssert(NO, @"ERROR: subclasses of %@ must implement the delegate flow layout method %@",
             [JSQMessagesViewController class],
             NSStringFromSelector(@selector(collectionView:layout:bubbleImageViewForItemAtIndexPath:sender:)));
    return nil;
}

- (UIImageView *)collectionView:(JSQMessagesCollectionView *)collectionView
                         layout:(JSQMessagesCollectionViewFlowLayout *)layout avatarImageViewForItemAtIndexPath:(NSIndexPath *)indexPath
                         sender:(NSString *)sender
{
    NSAssert(NO, @"ERROR: subclasses of %@ must implement the delegate flow layout method %@",
             [JSQMessagesViewController class],
             NSStringFromSelector(@selector(collectionView:layout:avatarImageViewForItemAtIndexPath:sender:)));
    return nil;
}

- (CGSize)collectionView:(UICollectionView *)collectionView
                  layout:(UICollectionViewLayout *)collectionViewLayout
  sizeForItemAtIndexPath:(NSIndexPath *)indexPath
{
    id<JSQMessageData> messageData = [self.collectionView.dataSource collectionView:self.collectionView
                                                          messageForItemAtIndexPath:indexPath];
    
    JSQMessagesCollectionViewFlowLayout *layout = (JSQMessagesCollectionViewFlowLayout *)collectionViewLayout;
    CGFloat cellWidth = collectionView.frame.size.width - layout.sectionInset.left - layout.sectionInset.right;
    
    CGFloat maxTextWidth = cellWidth
                            - kJSQMessagesCollectionViewCellAvatarSizeDefault
                            - kJSQMessagesCollectionViewCellMessageBubblePaddingDefault;
    
    UIEdgeInsets textInsets = [JSQMessagesCollectionViewCell defaultTextContainerInset];
    CGFloat textHorizontalPadding = textInsets.left + textInsets.right;
    CGFloat textVerticalPadding = textInsets.bottom + textInsets.top;
    CGFloat textPadding = textHorizontalPadding + textVerticalPadding;
    
    CGRect stringRect = [[messageData text] boundingRectWithSize:CGSizeMake(maxTextWidth - textPadding, CGFLOAT_MAX)
                                                         options:NSStringDrawingUsesLineFragmentOrigin | NSStringDrawingUsesFontLeading
                                                      attributes:@{
                                                                   NSFontAttributeName : [[JSQMessagesCollectionViewCell appearance] font],
                                                                   NSParagraphStyleAttributeName : [NSParagraphStyle defaultParagraphStyle]
                                                                   }
                                                         context:nil];
    
    CGFloat cellHeight = CGRectGetHeight(CGRectIntegral(stringRect));
    cellHeight += (kJSQMessagesCollectionViewCellLabelHeightDefault * 3.0f);
    cellHeight += textHorizontalPadding;
    
    return CGSizeMake(cellWidth, cellHeight);
}

#pragma mark - Input toolbar delegate

- (void)messagesInputToolbar:(JSQMessagesInputToolbar *)toolbar didPressLeftBarButton:(UIButton *)sender
{
    if (toolbar.sendButtonOnRight) {
        [self jsq_notifyDelegateDidPressAccessoryButton:sender];
    }
    else {
        [self jsq_notifyDelegateDidSendMessage];
    }
}

- (void)messagesInputToolbar:(JSQMessagesInputToolbar *)toolbar didPressRightBarButton:(UIButton *)sender
{
    if (toolbar.sendButtonOnRight) {
        [self jsq_notifyDelegateDidSendMessage];
    }
    else {
        [self jsq_notifyDelegateDidPressAccessoryButton:sender];
    }
}

- (void)jsq_notifyDelegateDidSendMessage
{
    JSQMessage *message = [JSQMessage messageWithText:[self.inputToolbar.contentView.textView.text jsq_stringByTrimingWhitespace]
                                               sender:self.sender];
    
    [self.delegate messagesViewController:self didSendMessage:message];
}

- (void)jsq_notifyDelegateDidPressAccessoryButton:(UIButton *)sender
{
    [self.delegate messagesViewController:self didPressAccessoryButton:sender];
}

#pragma mark - Text view delegate

- (void)textViewDidBeginEditing:(UITextView *)textView
{
    [textView becomeFirstResponder];
    
    if (self.autoScrollsToMostRecentMessage) {
        [self scrollToBottomAnimated:YES];
    }
}

- (void)textViewDidChange:(UITextView *)textView
{
    [self.inputToolbar toggleSendButtonEnabled];
}

- (void)textViewDidEndEditing:(UITextView *)textView
{
    [textView resignFirstResponder];
}

#pragma mark - Key-value observing

- (void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object change:(NSDictionary *)change context:(void *)context
{
    if (context == kJSQMessagesKeyValueObservingContext) {
        
        if (object == self.inputToolbar.contentView.textView
            && [keyPath isEqualToString:NSStringFromSelector(@selector(contentSize))]) {
            
            CGSize oldContentSize = [[change objectForKey:NSKeyValueChangeOldKey] CGSizeValue];
            CGSize newContentSize = [[change objectForKey:NSKeyValueChangeNewKey] CGSizeValue];
            
            CGFloat dy = newContentSize.height - oldContentSize.height;
        
            [self jsq_adjustInputToolbarForComposerTextViewContentSizeChange:dy];
        }
    }
}

#pragma mark - Keyboard control utilities

- (void)jsq_configureKeyboardControl
{
    __weak JSQMessagesViewController *weakSelf = self;
    __weak UIView *weakView = self.view;
    __weak JSQMessagesInputToolbar *weakInputToolbar = self.inputToolbar;
    __weak NSLayoutConstraint *weakToolbarBottomLayoutGuide = self.toolbarBottomLayoutGuide;
    
    [self.view addKeyboardPanningWithActionHandler:^(CGRect keyboardFrameInView) {
        CGRect newToolbarFrame = weakInputToolbar.frame;
        newToolbarFrame.origin.y = CGRectGetMinY(keyboardFrameInView) - CGRectGetHeight(newToolbarFrame);
        weakInputToolbar.frame = newToolbarFrame;
        
        CGFloat heightFromBottom = CGRectGetHeight(weakView.frame) - CGRectGetMinY(keyboardFrameInView);
        weakToolbarBottomLayoutGuide.constant = heightFromBottom;
        [weakSelf.view setNeedsUpdateConstraints];
        
        [weakSelf jsq_updateCollectionViewInsets];
    }];
}

- (void)jsq_updateKeyboardTriggerOffset
{
    self.view.keyboardTriggerOffset = CGRectGetHeight(self.inputToolbar.bounds);
}

#pragma mark - Input toolbar utilities

- (BOOL)jsq_inputToolbarHasReachedMaximumHeight
{
    return (CGRectGetMinY(self.inputToolbar.frame) == self.topLayoutGuide.length);
}

- (void)jsq_adjustInputToolbarForComposerTextViewContentSizeChange:(CGFloat)dy
{
    BOOL contentSizeIsIncreasing = (dy > 0);
    
    if ([self jsq_inputToolbarHasReachedMaximumHeight]) {
        BOOL contentOffsetIsPositive = (self.inputToolbar.contentView.textView.contentOffset.y > 0);
        
        if (contentSizeIsIncreasing || contentOffsetIsPositive) {
            [self jsq_scrollComposerTextViewToBottomAnimated:YES];
            return;
        }
    }
    
    CGFloat toolbarOriginY = CGRectGetMinY(self.inputToolbar.frame);
    CGFloat newToolbarOriginY = toolbarOriginY - dy;
    
    //  attempted to increase origin.Y above topLayoutGuide
    if (newToolbarOriginY <= self.topLayoutGuide.length) {
        dy = toolbarOriginY - self.topLayoutGuide.length;
        [self jsq_scrollComposerTextViewToBottomAnimated:YES];
    }
    
    [self jsq_adjustInputToolbarHeightConstraintByDelta:dy];
    
    [self jsq_updateKeyboardTriggerOffset];
    
    if (dy < 0) {
        [self jsq_scrollComposerTextViewToBottomAnimated:NO];
    }
}

- (void)jsq_adjustInputToolbarHeightConstraintByDelta:(CGFloat)dy
{
    self.toolbarHeightContraint.constant += dy;
    
    if (self.toolbarHeightContraint.constant < kJSQMessagesInputToolbarHeightDefault) {
        self.toolbarHeightContraint.constant = kJSQMessagesInputToolbarHeightDefault;
    }
    
    [self.view setNeedsUpdateConstraints];
    [self.view layoutIfNeeded];
}

- (void)jsq_scrollComposerTextViewToBottomAnimated:(BOOL)animated
{
    UITextView *textView = self.inputToolbar.contentView.textView;
    CGPoint contentOffsetToShowLastLine = CGPointMake(0.0f, textView.contentSize.height - CGRectGetHeight(textView.bounds));
    
    if (!animated) {
        textView.contentOffset = contentOffsetToShowLastLine;
        return;
    }
    
    [UIView animateWithDuration:0.01
                          delay:0.01
                        options:UIViewAnimationOptionCurveLinear
                     animations:^{
                         textView.contentOffset = contentOffsetToShowLastLine;
                     }
                     completion:nil];
}

#pragma mark - Collection view utilities

- (void)jsq_updateCollectionViewInsets
{
    [self jsq_setCollectionViewInsetsTopValue:self.topLayoutGuide.length
                                  bottomValue:CGRectGetHeight(self.collectionView.frame) - CGRectGetMinY(self.inputToolbar.frame)];
}

- (void)jsq_setCollectionViewInsetsTopValue:(CGFloat)top bottomValue:(CGFloat)bottom
{
    UIEdgeInsets insets = UIEdgeInsetsMake(top, 0.0f, bottom, 0.0f);
    self.collectionView.contentInset = insets;
    self.collectionView.scrollIndicatorInsets = insets;
}

#pragma mark - Utilities

- (void)jsq_addObservers
{
    [self.inputToolbar.contentView.textView addObserver:self
                                             forKeyPath:NSStringFromSelector(@selector(contentSize))
                                                options:NSKeyValueObservingOptionOld | NSKeyValueObservingOptionNew
                                                context:kJSQMessagesKeyValueObservingContext];
}

- (void)jsq_removeObservers
{
    @try {
        [self.inputToolbar.contentView.textView removeObserver:self
                                                    forKeyPath:NSStringFromSelector(@selector(contentSize))
                                                       context:kJSQMessagesKeyValueObservingContext];
    }
    @catch (NSException *exception) {
        NSLog(@"%s EXCEPTION CAUGHT : %@, %@", __PRETTY_FUNCTION__, exception, [exception userInfo]);
    }
}

@end
