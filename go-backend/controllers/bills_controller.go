package controllers

import (
	"net/http"
	"strconv"

	"github.com/gin-gonic/gin"
	"github.com/romsar/gonertia/v2"
	"gorm.io/gorm"
	"sway-go/models"
)

// BillsController handles requests for bills.
type BillsController struct {
	Inertia *gonertia.Inertia
	DB      *gorm.DB
}

// NewBillsController creates a new BillsController.
func NewBillsController(inertia *gonertia.Inertia, db *gorm.DB) *BillsController {
	return &BillsController{Inertia: inertia, DB: db}
}

// Index handles the retrieval of bills.
func (bc *BillsController) Index(c *gin.Context) {
	// For now, we will assume a placeholder for the current user.
	// Later, we will add logic to get the current user.
	// currentUser := &models.User{ID: 1}

	var bills []models.Bill
	user, exists := c.Get("user")
	if !exists {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "Unauthorized"})
		return
	}
	currentUser := user.(*models.User)

	bc.DB.Joins("JOIN user_bills ON user_bills.bill_id = bills.id").Where("user_bills.user_id = ?", currentUser.ID).Find(&bills)

	bc.Inertia.Render(c.Writer, c.Request, "Pages/Bills", gonertia.Props{
		"bills": bills,
	})
}

// Show handles the retrieval of a single bill.
func (bc *BillsController) Show(c *gin.Context) {
	var bill models.Bill
	if err := bc.DB.First(&bill, c.Param("id")).Error; err != nil {
		c.JSON(http.StatusNotFound, gin.H{"error": "Bill not found."})
		return
	}

	bc.Inertia.Render(c.Writer, c.Request, "Pages/Bill", gonertia.Props{
		"bill": bill,
	})
}

// New handles the creation of a new bill.
func (bc *BillsController) New(c *gin.Context) {
	bc.Inertia.Render(c.Writer, c.Request, "Pages/BillCreator", gonertia.Props{
		"bill": models.Bill{},
	})
}

// Edit handles the editing of a bill.
func (bc *BillsController) Edit(c *gin.Context) {
	var bill models.Bill
	if err := bc.DB.First(&bill, c.Param("id")).Error; err != nil {
		c.JSON(http.StatusNotFound, gin.H{"error": "Bill not found."})
		return
	}

	bc.Inertia.Render(c.Writer, c.Request, "Pages/BillCreator", gonertia.Props{
		"bill": bill,
	})
}

// Create handles the creation of a bill.
func (bc *BillsController) Create(c *gin.Context) {
	var bill models.Bill
	if err := c.ShouldBindJSON(&bill); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	if err := bc.DB.Create(&bill).Error; err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Failed to create bill."})
		return
	}

	c.Redirect(http.StatusFound, "/bills/"+strconv.Itoa(int(bill.ID)))
}

// Update handles the updating of a bill.
func (bc *BillsController) Update(c *gin.Context) {
	var bill models.Bill
	if err := bc.DB.First(&bill, c.Param("id")).Error; err != nil {
		c.JSON(http.StatusNotFound, gin.H{"error": "Bill not found."})
		return
	}

	if err := c.ShouldBindJSON(&bill); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	if err := bc.DB.Save(&bill).Error; err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Failed to update bill."})
		return
	}

	c.Redirect(http.StatusFound, "/bills/"+strconv.Itoa(int(bill.ID)))
}

// Destroy handles the deletion of a bill.
func (bc *BillsController) Destroy(c *gin.Context) {
	var bill models.Bill
	if err := bc.DB.First(&bill, c.Param("id")).Error; err != nil {
		c.JSON(http.StatusNotFound, gin.H{"error": "Bill not found."})
		return
	}

	if err := bc.DB.Delete(&bill).Error; err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Failed to delete bill."})
		return
	}

	c.Redirect(http.StatusFound, "/bills")
}
