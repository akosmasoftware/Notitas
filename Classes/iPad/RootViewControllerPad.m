//
//  RootViewControllerPad.m
//  Notitas
//
//  Created by Adrian on 9/16/11.
//  Copyright 2011 akosma software. All rights reserved.
//

#import "RootViewControllerPad.h"
#import "MNOHelpers.h"
#import "Note.h"
#import "NoteThumbnail.h"
#import "MapControllerPad.h"

#define DEFAULT_WIDTH 200.0
static CGRect DEFAULT_RECT = {{0.0, 0.0}, {DEFAULT_WIDTH, DEFAULT_WIDTH}};

@interface RootViewControllerPad ()

@property (nonatomic, retain) NSArray *notes;
@property (nonatomic, retain) NSMutableArray *noteViews;
@property (nonatomic, retain) CLLocationManager *locationManager;
@property (nonatomic) BOOL locationInformationAvailable;
@property (nonatomic, assign) NoteThumbnail *currentThumbnail;
@property (nonatomic, retain) UIAlertView *deleteAllNotesAlertView;
@property (nonatomic, retain) UIAlertView *deleteNoteAlertView;
@property (nonatomic, getter = isShowingLocationView) BOOL showingLocationView;
@property (nonatomic, getter = isShowingEditionView) BOOL showingEditionView;
@property (nonatomic, retain) MapControllerPad *map;

- (void)refresh;
- (Note *)createNote;
- (void)checkTrashIconEnabled;
- (void)scrollNoteIntoView:(Note *)note;
- (void)checkUndoButtonEnabled;
- (void)checkRedoButtonEnabled;
- (void)deleteCurrentNote;
- (void)editCurrentNote;
- (void)animateThumbnailAndPerformSelector:(SEL)selector;

@end



@implementation RootViewControllerPad

@synthesize notes = _notes;
@synthesize noteViews = _noteViews;
@synthesize trashButton = _trashButton;
@synthesize locationButton = _locationButton;
@synthesize locationManager = _locationManager;
@synthesize locationInformationAvailable = _locationInformationAvailable;
@synthesize holderView = _holderView;
@synthesize scrollView = _scrollView;
@synthesize currentThumbnail = _currentThumbnail;
@synthesize deleteAllNotesAlertView = _deleteAllNotesAlertView;
@synthesize deleteNoteAlertView = _deleteNoteAlertView;
@synthesize auxiliaryView = _auxiliaryView;
@synthesize mapView = _mapView;
@synthesize flipView = _flipView;
@synthesize undoButton = _undoButton;
@synthesize redoButton = _redoButton;
@synthesize modalBlockerView = _modalBlockerView;
@synthesize showingLocationView = _showingLocationView;
@synthesize showingEditionView = _showingEditionView;
@synthesize editorView = _editorView;
@synthesize textView = _textView;
@synthesize map = _map;

- (void)dealloc
{
    [_map release];
    [_textView release];
    [_editorView release];
    [_modalBlockerView release];
    [_undoButton release];
    [_redoButton release];
    [_flipView release];
    [_auxiliaryView release];
    [_mapView release];
    _currentThumbnail = nil;
    [_deleteAllNotesAlertView release];
    [_deleteNoteAlertView release];
    [_scrollView release];
    [_holderView release];
    [_locationManager release];
    [_trashButton release];
    [_locationButton release];
    [_notes release];
    [_noteViews release];
    [super dealloc];
}

#pragma mark - View lifecycle

- (void)viewDidLoad
{
    [super viewDidLoad];
    
    self.locationManager = [[[CLLocationManager alloc] init] autorelease];
    self.locationManager.delegate = self;
    self.locationManager.desiredAccuracy = kCLLocationAccuracyBest;
    self.locationManager.distanceFilter = 100;
    [self.locationManager startUpdatingLocation];

    self.scrollView.contentSize = CGSizeMake(1024.0, 1004.0);

    self.locationInformationAvailable = NO;
    self.showingLocationView = NO;
    self.showingEditionView = NO;
    self.modalBlockerView.alpha = 0.0;
    
    UITapGestureRecognizer *tap = [[[UITapGestureRecognizer alloc] initWithTarget:self 
                                                                           action:@selector(dismissBlockerView:)] autorelease];
    [self.modalBlockerView addGestureRecognizer:tap];
    
    [[NSNotificationCenter defaultCenter] addObserver:self 
                                             selector:@selector(undoManagerDidUndo:) 
                                                 name:NSUndoManagerDidUndoChangeNotification 
                                               object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self 
                                             selector:@selector(undoManagerDidRedo:) 
                                                 name:NSUndoManagerDidRedoChangeNotification 
                                               object:nil];

    [self refresh];
    [self checkTrashIconEnabled];
    [self checkUndoButtonEnabled];
    [self checkRedoButtonEnabled];
}

- (BOOL)shouldAutorotateToInterfaceOrientation:(UIInterfaceOrientation)interfaceOrientation
{
	return YES;
}

#pragma mark - UIResponderStandardEditActions methods

- (BOOL)canBecomeFirstResponder
{
    return YES;
}

- (void)delete:(id)sender
{
    if (self.deleteNoteAlertView == nil)
    {
        NSString *title = NSLocalizedString(@"Are you sure?", @"Title of the 'trash' dialog of the editor controller");
        NSString *message = NSLocalizedString(@"This action cannot be undone.", @"Explanation of the 'trash' dialog of the editor controller");
        NSString *cancelText = NSLocalizedString(@"Cancel", @"The 'cancel' word");
        self.deleteNoteAlertView = [[[UIAlertView alloc] initWithTitle:title
                                                               message:message
                                                              delegate:self
                                                     cancelButtonTitle:cancelText
                                                     otherButtonTitles:@"OK", nil] autorelease];
    }
    [self.deleteNoteAlertView show];
}

- (void)copy:(id)sender
{
    UIPasteboard *board = [UIPasteboard generalPasteboard];
    board.string = self.currentThumbnail.note.contents;
    self.currentThumbnail = nil;
}

- (void)cut:(id)sender
{
    UIPasteboard *board = [UIPasteboard generalPasteboard];
    board.string = self.currentThumbnail.note.contents;
    [self deleteCurrentNote];
}

- (void)paste:(id)sender
{
    UIPasteboard *board = [UIPasteboard generalPasteboard];
    [self createNewNoteWithContents:board.string];
}

- (void)showMap:(id)sender
{
    [self animateThumbnailAndPerformSelector:@selector(transitionToMap)];
}

#pragma mark - UIAlertViewDelegate methods

- (void)alertView:(UIAlertView *)alertView clickedButtonAtIndex:(NSInteger)buttonIndex
{
    switch (buttonIndex) 
    {
        case 0:
            // Cancel
            break;
            
        case 1:
        {
            // OK
            if (alertView == self.deleteNoteAlertView)
            {
                [self deleteCurrentNote];
            }
            else if (alertView == self.deleteAllNotesAlertView)
            {
                [[MNOCoreDataManager sharedMNOCoreDataManager] beginUndoGrouping];
                [[MNOCoreDataManager sharedMNOCoreDataManager] deleteAllObjectsOfType:@"Note"];
                [[MNOCoreDataManager sharedMNOCoreDataManager] endUndoGrouping];
                [[MNOSoundManager sharedMNOSoundManager] playEraseSound];
                [self refresh];
                self.trashButton.enabled = NO;
            }
            break;
        }
            
        default:
            break;
    }
}

#pragma mark - Gesture recognizer handlers

- (void)drag:(UIPanGestureRecognizer *)recognizer
{
    NoteThumbnail *thumb = (NoteThumbnail *)recognizer.view;
    self.currentThumbnail = thumb;

    if (recognizer.state == UIGestureRecognizerStateBegan)
    {
        [[MNOCoreDataManager sharedMNOCoreDataManager] beginUndoGrouping];
        [self.holderView bringSubviewToFront:thumb];
    }
    else if (recognizer.state == UIGestureRecognizerStateChanged)
    {
        CGPoint point = [recognizer locationInView:self.holderView];
        thumb.center = point;
        thumb.note.position = point;
    }
    else if (recognizer.state == UIGestureRecognizerStateEnded)
    {
        [[MNOCoreDataManager sharedMNOCoreDataManager] save];
        [[MNOCoreDataManager sharedMNOCoreDataManager] endUndoGrouping];
        [self checkUndoButtonEnabled];
        [self checkRedoButtonEnabled];
    }
}

//- (void)pinch:(UIPinchGestureRecognizer *)recognizer
//{
//    NoteThumbnail *thumb = (NoteThumbnail *)recognizer.view;
//    self.currentThumbnail = thumb;
//
//    if (recognizer.state == UIGestureRecognizerStateBegan)
//    {
//        [[MNOCoreDataManager sharedMNOCoreDataManager] beginUndoGrouping];
//        [self.holderView bringSubviewToFront:thumb];
//        thumb.originalTransform = thumb.transform;
//    }    
//    else if (recognizer.state == UIGestureRecognizerStateChanged)
//    {
//        if (thumb.note.scale > 0.5 && thumb.note.scale < 2.0)
//        {
//            CGFloat scale = recognizer.scale;
//            thumb.transform = CGAffineTransformScale(thumb.originalTransform, scale, scale);
//            thumb.note.scale = recognizer.scale;
//        }
//    }
//    else if (recognizer.state == UIGestureRecognizerStateEnded)
//    {
//        [[MNOCoreDataManager sharedMNOCoreDataManager] save];
//        [[MNOCoreDataManager sharedMNOCoreDataManager] endUndoGrouping];
//        [self checkUndoButtonEnabled];
//        [self checkRedoButtonEnabled];
//    }
//}

- (void)rotate:(UIRotationGestureRecognizer *)recognizer
{
    NoteThumbnail *thumb = (NoteThumbnail *)recognizer.view;
    self.currentThumbnail = thumb;

    if (recognizer.state == UIGestureRecognizerStateBegan)
    {
        [[MNOCoreDataManager sharedMNOCoreDataManager] beginUndoGrouping];
        [self.holderView bringSubviewToFront:thumb];
        thumb.originalTransform = thumb.transform;
    }
    else if (recognizer.state == UIGestureRecognizerStateChanged)
    {
        CGFloat angle = recognizer.rotation;
        thumb.transform = CGAffineTransformRotate(thumb.originalTransform, angle);
    }
    else if (recognizer.state == UIGestureRecognizerStateEnded)
    {
        CGFloat angle = recognizer.rotation;
        thumb.note.angleRadians += angle;
        [[MNOCoreDataManager sharedMNOCoreDataManager] save];
        [[MNOCoreDataManager sharedMNOCoreDataManager] endUndoGrouping];
        [self checkUndoButtonEnabled];
        [self checkRedoButtonEnabled];
    }
}

- (void)tap:(UITapGestureRecognizer *)recognizer
{
    NoteThumbnail *thumb = (NoteThumbnail *)recognizer.view;
    self.currentThumbnail = thumb;
    
    if (recognizer.state == UIGestureRecognizerStateRecognized)
    {
        [self becomeFirstResponder];
        [self.holderView bringSubviewToFront:thumb];
        
        NSString *locationText = NSLocalizedString(@"View location", @"Button to view the note location");
        BOOL locationAvailable = [thumb.note.hasLocation boolValue];
        if (locationAvailable)
        {
            UIMenuItem *locationItem = [[[UIMenuItem alloc] initWithTitle:locationText action:@selector(showMap:)] autorelease];
            NSArray *items = [NSArray arrayWithObjects:locationItem, nil];
            [UIMenuController sharedMenuController].menuItems = items;
        }
        
        [[UIMenuController sharedMenuController] setTargetRect:CGRectInset(thumb.frame, 50.0, 50.0)
                                                        inView:self.holderView];
        [[UIMenuController sharedMenuController] setMenuVisible:YES 
                                                       animated:YES];
    }    
}

- (void)doubleTap:(UITapGestureRecognizer *)recognizer
{
    NoteThumbnail *thumb = (NoteThumbnail *)recognizer.view;
    self.currentThumbnail = thumb;

    if (recognizer.state == UIGestureRecognizerStateRecognized)
    {
        [self becomeFirstResponder];
        [self.holderView bringSubviewToFront:thumb];
        
        [self editCurrentNote];
    }    
}

- (void)dismissBlockerView:(UITapGestureRecognizer *)recognizer
{
    if (self.isShowingLocationView)
    {
        [self.auxiliaryView mno_removeShadow];
        [UIView transitionWithView:self.auxiliaryView
                          duration:0.3
                           options:UIViewAnimationOptionAllowAnimatedContent + 
                                   UIViewAnimationOptionTransitionFlipFromRight + 
                                   UIViewAnimationOptionCurveEaseInOut
                        animations:^{
                            self.modalBlockerView.alpha = 0.0;
                            [self.auxiliaryView addSubview:self.currentThumbnail];
                            [self.flipView removeFromSuperview];
                        }
                        completion:^(BOOL finished) {
                            if (finished)
                            {
                                self.auxiliaryView.hidden = YES;
                                [self.holderView addSubview:self.currentThumbnail];
                                CGRect rect = [self.holderView convertRect:self.auxiliaryView.frame
                                                                  fromView:self.view];
                                self.currentThumbnail.frame = rect;
                                [UIView animateWithDuration:0.3 
                                                 animations:^{
                                                     self.currentThumbnail.frame = [self.currentThumbnail.note frameForWidth:DEFAULT_WIDTH];
                                                     [self.currentThumbnail refreshDisplay];
                                                 }
                                                 completion:^(BOOL finished) {
                                                     if (finished)
                                                     {
                                                         [self.currentThumbnail mno_addShadow];
                                                         self.showingLocationView = NO;
                                                     }
                                                 }];
                            }
                        }];
    }
    else if (self.isShowingEditionView)
    {
        self.currentThumbnail.note.contents = self.textView.text;
        self.auxiliaryView.hidden = YES;
        [self.editorView removeFromSuperview];
        [self.holderView addSubview:self.currentThumbnail];
        CGRect rect = [self.holderView convertRect:self.auxiliaryView.frame
                                          fromView:self.view];
        self.currentThumbnail.frame = rect;
        [self becomeFirstResponder];

        [UIView animateWithDuration:0.3 
                         animations:^{
                             self.textView.alpha = 0.0;
                             self.modalBlockerView.alpha = 0.0;
                             self.currentThumbnail.summaryLabel.alpha = 1.0;
                             self.currentThumbnail.frame = [self.currentThumbnail.note frameForWidth:DEFAULT_WIDTH];
                             [self.currentThumbnail refreshDisplay];
                         }
                         completion:^(BOOL finished) {
                             if (finished)
                             {
                                 [self.currentThumbnail mno_addShadow];
                                 self.showingEditionView = NO;
                                 [UIView animateWithDuration:0.3 
                                                  animations:^{
                                                      [self.currentThumbnail refreshDisplay];
                                                  }];
                             }
                         }];
    }
}

#pragma mark - CLLocationManagerDelegate methods

- (void)locationManager:(CLLocationManager *)manager 
    didUpdateToLocation:(CLLocation *)newLocation 
           fromLocation:(CLLocation *)oldLocation
{
    int latitude = (int)newLocation.coordinate.latitude;
    int longitude = (int)newLocation.coordinate.longitude;
    if (latitude != 0 && longitude != 0)
    {
        self.locationInformationAvailable = YES;
        self.locationButton.enabled = YES;
    }
}

- (void)locationManager:(CLLocationManager *)manager didFailWithError:(NSError *)error
{
    [self.locationManager stopUpdatingLocation];
    self.locationInformationAvailable = NO;
}

#pragma mark - UITextViewDelegate methods

- (BOOL)textViewShouldEndEditing:(UITextView *)textView
{
    [self.textView resignFirstResponder];
    [self becomeFirstResponder];
    [self dismissBlockerView:nil];
    return YES;
}

#pragma mark - Public methods

- (IBAction)undo:(id)sender
{
    [[[MNOCoreDataManager sharedMNOCoreDataManager] undoManager] undo];
    [self checkUndoButtonEnabled];
    [self checkRedoButtonEnabled];
}

- (IBAction)redo:(id)sender
{
    [[[MNOCoreDataManager sharedMNOCoreDataManager] undoManager] redo];
    [self checkUndoButtonEnabled];
    [self checkRedoButtonEnabled];
}

- (IBAction)showMapWithAllNotes:(id)sender
{
    if (self.map == nil)
    {
        self.map = [[[MapControllerPad alloc] init] autorelease];
        self.map.parent = self;
    }
    [UIView transitionFromView:self.view 
                        toView:self.map.view
                      duration:0.5
                       options:UIViewAnimationOptionTransitionFlipFromLeft
                    completion:nil];
}

- (void)createNewNoteWithContents:(NSString *)contents
{
    [[MNOCoreDataManager sharedMNOCoreDataManager] beginUndoGrouping];
	Note *newNote = [self createNote];
    newNote.contents = contents;
    
    [[MNOCoreDataManager sharedMNOCoreDataManager] save];
    [[MNOCoreDataManager sharedMNOCoreDataManager] endUndoGrouping];

    [self refresh];
    [self scrollNoteIntoView:newNote];
}

- (IBAction)shakeNotes:(id)sender
{
    [[MNOCoreDataManager sharedMNOCoreDataManager] shakeNotes];
    [self refresh];
}

- (IBAction)newNoteWithLocation:(id)sender
{
    if (self.locationInformationAvailable)
    {
        [[MNOCoreDataManager sharedMNOCoreDataManager] beginUndoGrouping];
        Note *newNote = [self createNote];
        CLLocationDegrees latitude = _locationManager.location.coordinate.latitude;
        CLLocationDegrees longitude = _locationManager.location.coordinate.longitude;
        NSString *template = NSLocalizedString(@"Current location:\n\nLatitude: %1.3f\nLongitude: %1.3f", @"Message created by the 'location' button");
        newNote.contents = [NSString stringWithFormat:template, latitude, longitude];
        
        [[MNOCoreDataManager sharedMNOCoreDataManager] save];
        [[MNOCoreDataManager sharedMNOCoreDataManager] endUndoGrouping];
        [self refresh];
        self.trashButton.enabled = YES;
        [self scrollNoteIntoView:newNote];
    }
}

- (IBAction)removeAllNotes:(id)sender
{
    if (self.deleteAllNotesAlertView == nil)
    {
        NSString *title = NSLocalizedString(@"Remove all the notes?", @"Title of the 'remove all notes' dialog");
        NSString *message = NSLocalizedString(@"You will remove all the notes!\nThis action cannot be undone.", @"Warning message of the 'remove all notes' dialog");
        NSString *cancelText = NSLocalizedString(@"Cancel", @"The 'cancel' word");
        self.deleteAllNotesAlertView = [[[UIAlertView alloc] initWithTitle:title
                                                                   message:message
                                                                  delegate:self
                                                         cancelButtonTitle:cancelText
                                                         otherButtonTitles:@"OK", nil] autorelease];
    }
    [self.deleteAllNotesAlertView show];
}

- (IBAction)about:(id)sender
{
    [[MNOCoreDataManager sharedMNOCoreDataManager] beginUndoGrouping];
	Note *newNote = [self createNote];
    
    NSString *copyright = NSLocalizedString(@"Notitas by akosma\nhttp://akosma.com\nCopyright 2009-2011 © akosma software\nAll Rights Reserved", @"Copyright text");
    newNote.contents = copyright;
    
    [[MNOCoreDataManager sharedMNOCoreDataManager] save];
    [[MNOCoreDataManager sharedMNOCoreDataManager] endUndoGrouping];
    [self refresh];
    self.trashButton.enabled = YES;

    [self scrollNoteIntoView:newNote];
}

- (IBAction)insertNewObject:(id)sender
{
    [[MNOCoreDataManager sharedMNOCoreDataManager] beginUndoGrouping];
	Note *newNote = [self createNote];
    
    [[MNOCoreDataManager sharedMNOCoreDataManager] save];
    [self refresh];
    self.trashButton.enabled = YES;
    [self scrollNoteIntoView:newNote];
    [[MNOCoreDataManager sharedMNOCoreDataManager] endUndoGrouping];
}

#pragma mark - Undo support

- (void)undoManagerDidUndo:(NSNotification *)notification 
{
	[self refresh];
    [self checkTrashIconEnabled];
}

- (void)undoManagerDidRedo:(NSNotification *)notification 
{
	[self refresh];
    [self checkTrashIconEnabled];
}

#pragma mark - Private methods

- (void)refresh
{
    self.notes = [[MNOCoreDataManager sharedMNOCoreDataManager] allNotes];
    [self.noteViews makeObjectsPerformSelector:@selector(removeFromSuperview)];
    self.noteViews = [NSMutableArray array];
    for (Note *note in self.notes)
    {
        NoteThumbnail *thumb = [[[NoteThumbnail alloc] initWithFrame:DEFAULT_RECT] autorelease];
        thumb.note = note;
        [thumb refreshDisplay];
        
        UIPanGestureRecognizer *pan = [[[UIPanGestureRecognizer alloc] initWithTarget:self
                                                                               action:@selector(drag:)] autorelease];
//        UIPinchGestureRecognizer *pinch = [[[UIPinchGestureRecognizer alloc] initWithTarget:self 
//                                                                                     action:@selector(pinch:)] autorelease];
        UIRotationGestureRecognizer *rotation = [[[UIRotationGestureRecognizer alloc] initWithTarget:self 
                                                                                              action:@selector(rotate:)] autorelease];
        UITapGestureRecognizer *tap = [[[UITapGestureRecognizer alloc] initWithTarget:self 
                                                                               action:@selector(tap:)] autorelease];
        UITapGestureRecognizer *doubleTap = [[[UITapGestureRecognizer alloc] initWithTarget:self 
                                                                                     action:@selector(doubleTap:)] autorelease];
        doubleTap.numberOfTapsRequired = 2;
        
        [thumb addGestureRecognizer:pan];
//        [thumb addGestureRecognizer:pinch];
        [thumb addGestureRecognizer:rotation];
        [thumb addGestureRecognizer:tap];
        [thumb addGestureRecognizer:doubleTap];
        
        [self.noteViews addObject:thumb];
        [self.holderView addSubview:thumb];
        [thumb mno_addShadow];
    }
    [self checkUndoButtonEnabled];
    [self checkRedoButtonEnabled];
}

- (Note *)createNote
{
	Note *newNote = [[MNOCoreDataManager sharedMNOCoreDataManager] createNote];
    
    newNote.hasLocation = [NSNumber numberWithBool:self.locationInformationAvailable];
    if (self.locationInformationAvailable)
    {
        newNote.latitude = [NSNumber numberWithDouble:self.locationManager.location.coordinate.latitude];
        newNote.longitude = [NSNumber numberWithDouble:self.locationManager.location.coordinate.longitude];
    }
    return newNote;
}

- (void)checkTrashIconEnabled
{
    self.trashButton.enabled = ([self.notes count] > 0);
}

- (void)checkUndoButtonEnabled
{
    self.undoButton.enabled = [[[MNOCoreDataManager sharedMNOCoreDataManager] undoManager] canUndo];
}

- (void)checkRedoButtonEnabled
{
    self.redoButton.enabled = [[[MNOCoreDataManager sharedMNOCoreDataManager] undoManager] canRedo];
}

- (void)scrollNoteIntoView:(Note *)note
{
    CGPoint point = note.position;
    CGRect rect = CGRectMake(point.x - 100.0, point.y - 100.0, 200.0, 200.0);
    [self.scrollView scrollRectToVisible:rect animated:YES];
    self.trashButton.enabled = YES;
}

- (void)deleteCurrentNote
{
    if (self.currentThumbnail != nil)
    {
        [[MNOCoreDataManager sharedMNOCoreDataManager] beginUndoGrouping];
        [[MNOCoreDataManager sharedMNOCoreDataManager] deleteObject:self.currentThumbnail.note];
        [[MNOCoreDataManager sharedMNOCoreDataManager] endUndoGrouping];

        [UIView animateWithDuration:0.5
                      animations:^{
                          self.currentThumbnail.alpha = 0.0;
                      } 
                      completion:^(BOOL finished){
                          [self.currentThumbnail removeFromSuperview];
                          self.currentThumbnail = nil;
                          [[MNOSoundManager sharedMNOSoundManager] playEraseSound];
                          [self refresh];
                          [self checkTrashIconEnabled];
                      }];
    }
}

- (void)editCurrentNote
{
    [self animateThumbnailAndPerformSelector:@selector(transitionToEdition)];
}

- (void)animateThumbnailAndPerformSelector:(SEL)selector
{
    [self.currentThumbnail mno_removeShadow];
    [self.view addSubview:self.currentThumbnail];
    CGRect rect = [self.view convertRect:self.currentThumbnail.frame
                                fromView:self.holderView];
    self.currentThumbnail.frame = rect;
    
    [UIView animateWithDuration:0.3 
                     animations:^{
                         self.currentThumbnail.transform = CGAffineTransformIdentity;
                         self.currentThumbnail.frame = self.auxiliaryView.frame;
                     } 
                     completion:^(BOOL finished) {
                         if (finished)
                         {
                             self.auxiliaryView.hidden = NO;
                             [self.auxiliaryView addSubview:self.currentThumbnail];
                             self.currentThumbnail.frame = self.auxiliaryView.bounds;
                             [self performSelector:selector
                                        withObject:nil
                                        afterDelay:0.1];
                         }
                     }];
}

- (void)transitionToMap
{
    [UIView transitionWithView:self.auxiliaryView
                      duration:0.3
                       options:UIViewAnimationOptionAllowAnimatedContent + 
     UIViewAnimationOptionTransitionFlipFromLeft + 
     UIViewAnimationOptionCurveEaseInOut
                    animations:^{
                        self.modalBlockerView.alpha = 1.0;
                        [self.auxiliaryView addSubview:self.flipView];
                        [self.currentThumbnail removeFromSuperview];
                    }
                    completion:^(BOOL finished) {
                        if (finished)
                        {
                            CLLocationCoordinate2D coordinate = self.currentThumbnail.note.location.coordinate;
                            self.mapView.centerCoordinate = coordinate;
                            MKCoordinateRegion region = MKCoordinateRegionMakeWithDistance(coordinate, 10000.0, 10000.0);
                            self.mapView.region = region;
                            [self.auxiliaryView mno_addShadow];
                            self.showingLocationView = YES;
                        }
                    }];
}

- (void)transitionToEdition
{
    [self.auxiliaryView addSubview:self.editorView];
    self.editorView.alpha = 0.0;
    self.textView.text = self.currentThumbnail.note.contents;
    self.textView.font = [UIFont fontWithName:fontNameForCode(self.currentThumbnail.note.fontCode) size:30.0];
    [UIView animateWithDuration:0.3
                     animations:^{
                         self.modalBlockerView.alpha = 1.0;
                         self.currentThumbnail.summaryLabel.alpha = 0.0;
                         self.editorView.alpha = 1.0;
                         self.textView.alpha = 1.0;
                     } 
                     completion:^(BOOL finished) {
                         [self.textView becomeFirstResponder];
                         self.showingEditionView = YES;
                     }];
}

@end
