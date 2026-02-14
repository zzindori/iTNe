class RecipeCard {
  final String id;
  final String title;
  final String summary;
  final List<String> mainIngredients;
  final int timeMinutes;
  final String categoryId;

  RecipeCard({
    required this.id,
    required this.title,
    required this.summary,
    required this.mainIngredients,
    required this.timeMinutes,
    required this.categoryId,
  });

  factory RecipeCard.fromJson(Map<String, dynamic> json) {
    return RecipeCard(
      id: json['id']?.toString() ?? '',
      title: json['title']?.toString() ?? '',
      summary: json['summary']?.toString() ?? '',
      mainIngredients: (json['mainIngredients'] as List<dynamic>? ?? [])
          .map((e) => e.toString())
          .toList(),
      timeMinutes: (json['timeMinutes'] as num?)?.toInt() ?? 0,
      categoryId: json['categoryId']?.toString() ?? '',
    );
  }
}

class RecipeDetail {
  final String id;
  final String title;
  final String summary;
  final String imageUrl;
  final String imagePath;
  final List<String> ingredients;
  final List<String> steps;
  final String tips;
  final int timeMinutes;
  final String servings;

  RecipeDetail({
    required this.id,
    required this.title,
    required this.summary,
    required this.imageUrl,
    required this.imagePath,
    required this.ingredients,
    required this.steps,
    required this.tips,
    required this.timeMinutes,
    required this.servings,
  });

  factory RecipeDetail.fromJson(Map<String, dynamic> json) {
    return RecipeDetail(
      id: json['id']?.toString() ?? '',
      title: json['title']?.toString() ?? '',
      summary: json['summary']?.toString() ?? '',
      imageUrl: json['imageUrl']?.toString() ?? '',
      imagePath: json['localImagePath']?.toString() ?? '',
      ingredients: (json['ingredients'] as List<dynamic>? ?? [])
          .map((e) => e.toString())
          .toList(),
      steps: (json['steps'] as List<dynamic>? ?? [])
          .map((e) => e.toString())
          .toList(),
      tips: json['tips']?.toString() ?? '',
      timeMinutes: (json['timeMinutes'] as num?)?.toInt() ?? 0,
      servings: json['servings']?.toString() ?? '',
    );
  }

  RecipeDetail copyWith({
    String? imageUrl,
    String? imagePath,
  }) {
    return RecipeDetail(
      id: id,
      title: title,
      summary: summary,
      imageUrl: imageUrl ?? this.imageUrl,
      imagePath: imagePath ?? this.imagePath,
      ingredients: ingredients,
      steps: steps,
      tips: tips,
      timeMinutes: timeMinutes,
      servings: servings,
    );
  }
}
